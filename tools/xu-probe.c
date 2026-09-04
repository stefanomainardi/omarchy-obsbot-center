#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/usb/video.h>
#include <linux/uvcvideo.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int query(int fd, uint8_t unit, uint8_t selector, uint8_t request,
                 void *data, uint16_t size) {
  struct uvc_xu_control_query control = {
      .unit = unit,
      .selector = selector,
      .query = request,
      .size = size,
      .data = data,
  };
  return ioctl(fd, UVCIOC_CTRL_QUERY, &control);
}

/* Gesture zoom travels as a ratio scaled by 100 (2x -> 200). The camera
   reports it back in quarter units, so 2x reads as 50. */
#define GESTURE_ZOOM_SCALE 100
#define GESTURE_ZOOM_DEFAULT 200
#define GESTURE_ZOOM_READ_UNITS 25

static int build_command(const char *name, const char *value,
                         uint8_t frame[60]) {
  memset(frame, 0, 60);

  if (strcmp(name, "fov") == 0) {
    if (strcmp(value, "wide") == 0)
      frame[2] = 0;
    else if (strcmp(value, "medium") == 0)
      frame[2] = 1;
    else if (strcmp(value, "narrow") == 0)
      frame[2] = 2;
    else
      return 2;
    frame[0] = 0x04;
    frame[1] = 0x01;
  } else if (strcmp(name, "auto-framing") == 0) {
    frame[0] = 0x0d;
    frame[1] = 0x02;
    if (strcmp(value, "off") == 0) {
      frame[2] = 0;
      frame[3] = 0;
    } else if (strcmp(value, "solo") == 0) {
      frame[2] = 1;
      frame[3] = 0;
    } else if (strcmp(value, "group") == 0) {
      frame[2] = 1;
      frame[3] = 1;
    } else {
      return 2;
    }
  } else if (strcmp(name, "audio-distance") == 0) {
    frame[0] = 0x1b;
    frame[1] = 0x01;
    if (strcmp(value, "standard") == 0)
      frame[2] = 0;
    else if (strcmp(value, "near") == 0)
      frame[2] = 1;
    else if (strcmp(value, "far") == 0)
      frame[2] = 2;
    else
      return 2;
  } else if (strcmp(name, "audio-mode") == 0) {
    frame[0] = 0x22;
    frame[1] = 0x02;
    frame[2] = 0x00;
    if (strcmp(value, "pure") == 0)
      frame[3] = 0x05;
    else if (strcmp(value, "omni") == 0)
      frame[3] = 0x00;
    else if (strcmp(value, "directional") == 0)
      frame[3] = 0x02;
    else if (strcmp(value, "dual-directional") == 0)
      frame[3] = 0x04;
    else
      return 2;
  } else if (strcmp(name, "gesture-control") == 0 &&
             (strcmp(value, "off") == 0 || strcmp(value, "on") == 0)) {
    uint8_t enabled = strcmp(value, "on") == 0;
    frame[0] = 0x20;
    frame[1] = 0x05;
    frame[2] = enabled;
    frame[3] = 0x02;
    frame[4] = enabled;
    /* The zoom factor shares this frame. Callers with an open device replace
       these two bytes with the factor already stored in the camera so that
       toggling gesture control never silently resets it. */
    frame[5] = GESTURE_ZOOM_DEFAULT & 0xff;
    frame[6] = (GESTURE_ZOOM_DEFAULT >> 8) & 0xff;
  } else if (strcmp(name, "gesture-zoom") == 0) {
    unsigned int factor;
    if (strcmp(value, "1x") == 0)
      factor = 1;
    else if (strcmp(value, "2x") == 0)
      factor = 2;
    else if (strcmp(value, "3x") == 0)
      factor = 3;
    else if (strcmp(value, "4x") == 0)
      factor = 4;
    else
      return 2;
    /* The firmware reads the factor as a fixed-point ratio scaled by 100, so
       2x travels as 200. Sending the bare multiplier lands far below 1.00x:
       the camera still recognizes the gesture and lights the LED, but applies
       no zoom at all. */
    factor *= GESTURE_ZOOM_SCALE;
    frame[0] = 0x20;
    frame[1] = 0x05;
    frame[2] = 0x01;
    frame[3] = 0x02;
    frame[4] = 0x01;
    frame[5] = factor & 0xff;
    frame[6] = (factor >> 8) & 0xff;
  } else if (strcmp(name, "auto-sleep") == 0) {
    unsigned int seconds = 0;
    if (strcmp(value, "off") == 0)
      seconds = 0;
    else if (strcmp(value, "30s") == 0)
      seconds = 30;
    else if (strcmp(value, "2m") == 0)
      seconds = 120;
    else if (strcmp(value, "10m") == 0)
      seconds = 600;
    else
      return 2;
    frame[0] = 0x0b;
    frame[1] = 0x02;
    frame[2] = seconds & 0xff;
    frame[3] = (seconds >> 8) & 0xff;
  } else if (strcmp(value, "off") == 0 || strcmp(value, "on") == 0) {
    frame[2] = strcmp(value, "on") == 0;
    if (strcmp(name, "mirror") == 0) {
      frame[0] = 0x14;
      frame[1] = 0x01;
    } else if (strcmp(name, "vertical") == 0) {
      frame[0] = 0x0c;
      frame[1] = 0x01;
    } else if (strcmp(name, "led") == 0) {
      frame[0] = 0x18;
      frame[1] = 0x01;
    } else if (strcmp(name, "keep-awake") == 0) {
      frame[0] = 0x12;
      frame[1] = 0x01;
    } else if (strcmp(name, "microphone") == 0) {
      frame[0] = 0x1c;
      frame[1] = 0x01;
    } else if (strcmp(name, "audio-agc") == 0) {
      frame[0] = 0x17;
      frame[1] = 0x01;
    } else if (strcmp(name, "sleep-microphone") == 0) {
      frame[0] = 0x13;
      frame[1] = 0x01;
    } else if (strcmp(name, "hdr") == 0) {
      frame[0] = 0x01;
      frame[1] = 0x01;
    } else {
      return 2;
    }
  } else {
    return 2;
  }

  return 0;
}

/* Returns the gesture zoom ratio scaled by 100, or 0 when the camera state
   cannot be read or holds a value outside the 1x to 4x range. */
static unsigned int read_gesture_zoom(int fd) {
  uint8_t current[60] = {0};
  if (query(fd, 2, 6, UVC_GET_CUR, current, sizeof(current)) != 0) return 0;
  unsigned int units = ((unsigned int)current[39] << 2) | (current[38] >> 6);
  if (units < GESTURE_ZOOM_READ_UNITS || units > 4 * GESTURE_ZOOM_READ_UNITS)
    return 0;
  if (units % GESTURE_ZOOM_READ_UNITS != 0) return 0;
  return (units / GESTURE_ZOOM_READ_UNITS) * GESTURE_ZOOM_SCALE;
}

static int send_command(int fd, const char *name, const char *value) {
  uint8_t frame[60];
  int result = build_command(name, value, frame);
  if (result != 0) return result;

  if (strcmp(name, "gesture-control") == 0) {
    unsigned int stored = read_gesture_zoom(fd);
    if (stored != 0) {
      frame[5] = stored & 0xff;
      frame[6] = (stored >> 8) & 0xff;
    }
  }

  if (query(fd, 2, 6, UVC_SET_CUR, frame, sizeof(frame)) != 0) {
    fprintf(stderr, "vendor command failed: %s\n", strerror(errno));
    return 1;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 4 && strcmp(argv[1], "--encode") == 0) {
    uint8_t frame[60];
    int result = build_command(argv[2], argv[3], frame);
    if (result != 0) {
      fprintf(stderr, "unsupported command or value\n");
      return result;
    }
    for (size_t i = 0; i < sizeof(frame); i++) printf("%02x", frame[i]);
    putchar('\n');
    return 0;
  }

  const char *device = argc > 1 ? argv[1] : "/dev/video0";
  int fd = open(device, O_RDWR | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) {
    fprintf(stderr, "cannot open %s: %s\n", device, strerror(errno));
    return 1;
  }

  if (argc == 5 && strcmp(argv[2], "set") == 0) {
    int result = send_command(fd, argv[3], argv[4]);
    if (result == 2)
      fprintf(stderr, "unsupported command or value\n");
    close(fd);
    return result;
  }

  if (argc == 3 && strcmp(argv[2], "state") == 0) {
    uint8_t current[60] = {0};
    if (query(fd, 2, 6, UVC_GET_CUR, current, sizeof(current)) != 0) {
      fprintf(stderr, "cannot read camera state: %s\n", strerror(errno));
      close(fd);
      return 1;
    }
    if (current[24] == 0)
      printf("auto_framing=off\n");
    else if (current[27] != 0)
      printf("auto_framing=group\n");
    else
      printf("auto_framing=solo\n");
    printf("hdr=%s\n", current[6] != 0 ? "on" : "off");
    printf("mirror=%s\n", current[19] != 0 ? "on" : "off");
    printf("gesture_control=%s\n",
           (current[38] & 0x09) == 0x09 ? "on" : "off");
    unsigned int zoom_units =
        ((unsigned int)current[39] << 2) | (current[38] >> 6);
    if (zoom_units >= GESTURE_ZOOM_READ_UNITS &&
        zoom_units <= 4 * GESTURE_ZOOM_READ_UNITS &&
        zoom_units % GESTURE_ZOOM_READ_UNITS == 0)
      printf("gesture_zoom=%ux\n", zoom_units / GESTURE_ZOOM_READ_UNITS);
    close(fd);
    return 0;
  }

  printf("device=%s\nunit=2\n", device);
  for (uint8_t selector = 1; selector <= 7; selector++) {
    uint8_t info = 0;
    uint8_t length_bytes[2] = {0, 0};
    int info_result = query(fd, 2, selector, UVC_GET_INFO, &info, sizeof(info));
    int info_error = errno;
    int length_result = query(fd, 2, selector, UVC_GET_LEN, length_bytes,
                              sizeof(length_bytes));
    int length_error = errno;
    uint16_t length = (uint16_t)length_bytes[0] | ((uint16_t)length_bytes[1] << 8);

    printf("selector=%u", selector);
    if (info_result == 0)
      printf(" info=0x%02x readable=%u writable=%u", info,
             (info & 0x01) != 0, (info & 0x02) != 0);
    else
      printf(" info_error=%s", strerror(info_error));

    if (length_result == 0)
      printf(" length=%u", length);
    else
      printf(" length_error=%s", strerror(length_error));
    putchar('\n');

    if (length_result == 0 && length > 0 && length <= 256 && (info & 0x01)) {
      uint8_t current[256] = {0};
      if (query(fd, 2, selector, UVC_GET_CUR, current, length) == 0) {
        printf("current=");
        for (uint16_t i = 0; i < length; i++) printf("%02x", current[i]);
        putchar('\n');
      } else {
        printf("current_error=%s\n", strerror(errno));
      }
    }
  }

  close(fd);
  return 0;
}
