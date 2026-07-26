# Known Issues

## VyOS Rolling — Keyboard unresponsive after boot

**Status:** Open  
**Distro:** VyOS Rolling (2026.07.21)  
**Symptom:** VyOS boots successfully (kernel + initrd + squashfs load fine), shows login prompt, but keyboard input has no effect.  
**Cause:** VyOS live-boot autologin repeatedly attempts to login as `user` (which doesn't exist) in a tight loop, flooding tty1 and preventing keyboard input from being processed.  
**Workaround:** None confirmed. Try switching to tty2 (Ctrl+Alt+F2) or using xterm.js console in Proxmox.  
**Note:** This is a VyOS ISO live-boot behavior, not a netboot-catalog issue. The PXE boot chain (kernel + initrd + squashfs fetch) completes successfully.

---

## iPXE Image Trust — Proxmox built-in iPXE ROM

**Status:** Resolved (workaround)  
**Symptom:** Proxmox/QEMU VMs have built-in iPXE ROM that enforces image signature verification. HTTP kernel downloads return "Operation not permitted".  
**Workaround:** Serve kernel/initrd via TFTP (not subject to image trust). Squashfs is fetched by the kernel post-boot via HTTP (not affected).  
**Long-term fix:** Build custom iPXE binary without IMAGE_TRUST, or use HTTPS with trusted certificate.
