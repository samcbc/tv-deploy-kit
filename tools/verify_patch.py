import struct, hashlib
from capstone import *

orig = open('boot.img', 'rb').read()
pat = open('boot_patched.img', 'rb').read()

print("=== 1. boot 头结构对比 ===")
fields = ['kernel_size','kernel_addr','ramdisk_size','ramdisk_addr','second_size',
          'second_addr','tags_addr','page_size','header_version','os_version']
for name, buf in (('原始', orig), ('补丁', pat)):
    vals = {}
    off = 8
    for f in fields:
        vals[f] = struct.unpack_from('<I', buf, off)[0]; off += 4
    print("  %s: kernel=%d ramdisk=%d page=%d" % (name, vals['kernel_size'], vals['ramdisk_size'], vals['page_size']))

print("\n=== 2. 差异定位 ===")
diff = [i for i in range(len(orig)) if orig[i] != pat[i]]
print("  差异字节数:", len(diff), "偏移:", [hex(x) for x in diff])

print("\n=== 3. 反汇编打补丁处 ===")
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
off = 0x3d5604
print("  原始:")
for ins in md.disasm(orig[off:off+16], 0xffffff8008454e04):
    print("    %#x: %-8s %s" % (ins.address, ins.mnemonic, ins.op_str))
print("  补丁后:")
for ins in md.disasm(pat[off:off+16], 0xffffff8008454e04):
    print("    %#x: %-8s %s" % (ins.address, ins.mnemonic, ins.op_str))

print("\n=== 4. 校验和 ===")
print("  原始 sha256:", hashlib.sha256(orig).hexdigest())
print("  补丁 sha256:", hashlib.sha256(pat).hexdigest())
print("  大小:", len(orig), len(pat))
