"""웹캠 영상을 흐리게 만들어 가상 카메라로 내보내는 최소 예제.

    python examples/blur_webcam.py

Zoom 등에서 카메라로 camsink 을 고르면 흐려진 화면이 나온다.
"""

import cv2

from camsink import VirtualCamera

capture = cv2.VideoCapture(0)
if not capture.isOpened():
    raise SystemExit("웹캠을 열 수 없습니다.")

with VirtualCamera() as cam:
    print("송출 중입니다. Ctrl+C 로 종료하세요.")
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                continue
            cam.send(cv2.GaussianBlur(frame, (51, 51), 0))
    except KeyboardInterrupt:
        pass

capture.release()
