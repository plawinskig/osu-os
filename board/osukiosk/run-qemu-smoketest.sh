#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")"

rm -f qemu-mon.sock qemu-serial.log qemu-screen.ppm

qemu-system-x86_64 \
	-kernel ../../../buildroot/output/images/bzImage \
	-append "console=tty1 console=ttyS0 loglevel=7" \
	-m 2048 \
	-device virtio-gpu-pci \
	-device qemu-xhci \
	-drive file=output/boot.vfat,if=none,id=usbboot,format=raw \
	-device usb-storage,drive=usbboot \
	-drive file=data.img,if=none,id=usbdata,format=raw \
	-device usb-storage,drive=usbdata \
	-serial file:qemu-serial.log \
	-monitor unix:qemu-mon.sock,server,nowait \
	-display none \
	-no-reboot &
QEMU_PID=$!

# Wait for the monitor socket to appear.
for i in $(seq 1 20); do
	[ -S qemu-mon.sock ] && break
	sleep 0.5
done

echo "QEMU PID $QEMU_PID, waiting 60s for boot to reach the session launcher..."
sleep 60

echo "screendump qemu-screen.ppm" | nc -U -q1 qemu-mon.sock >/dev/null
sleep 2
echo "quit" | nc -U -q1 qemu-mon.sock >/dev/null

wait "$QEMU_PID" 2>/dev/null
echo "QEMU exited."
