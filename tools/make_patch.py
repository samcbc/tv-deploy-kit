import struct, sys

BOOT = 'boot.img'
ORIG_PATTERN = bytes.fromhex('fd7bbda95f340071fd030091f30b00f9')  # cap_capable 前 16 字节
PATCH = bytes.fromhex('00008052c0035fd6')                          # mov w0,#0 ; ret
KERNEL_OFF = 0x800
KERNEL_SIZE = 15794688

boot = bytearray(open(BOOT, 'rb').read())
print("boot.img 大小:", len(boot))

hits = []
start = 0
while True:
    i = boot.find(ORIG_PATTERN, start)
    if i < 0:
        break
    hits.append(i)
    start = i + 1

print("命中次数:", len(hits), [hex(h) for h in hits])
if len(hits) != 1:
    print("命中不唯一，停止")
    sys.exit(1)

off = hits[0]
print("命中偏移 %#x，位于内核区内: %s" % (off, KERNEL_OFF <= off < KERNEL_OFF + KERNEL_SIZE))
print("内核内偏移 = %#x （VA ≈ %#x）" % (off - KERNEL_OFF, 0xffffff8008080000 + (off - KERNEL_OFF)))

# 再确认一次原始字节上下文
print("原始 32 字节:", boot[off:off+32].hex())

patched = bytearray(boot)
patched[off:off+8] = PATCH
open('boot_patched.img', 'wb').write(patched)

chk = open('boot_patched.img', 'rb').read()
print("\n补丁后字节:", chk[off:off+16].hex())
print("文件大小不变:", len(chk) == len(boot))
# 其余字节与原始一致（除该 8 字节）
diff = sum(1 for a, b in zip(chk, boot) if a != b)
print("全文件差异字节数:", diff)
