import struct, sys

d = open('boot.img', 'rb').read()
print("magic:", d[:8])
fields = ['kernel_size','kernel_addr','ramdisk_size','ramdisk_addr',
          'second_size','second_addr','tags_addr','page_size',
          'header_version','os_version']
off = 8
vals = {}
for f in fields:
    v = struct.unpack_from('<I', d, off)[0]; off += 4
    vals[f] = v
    print("  %-16s = %d (%#x)" % (f, v, v))
print("name:", d[off:off+16].rstrip(b'\0'))
print("cmdline:", d[off+16:off+16+512].rstrip(b'\0').decode('utf-8', 'replace'))
print("extra_cmdline:", d[off+16+512:off+16+512+1024].rstrip(b'\0').decode('utf-8','replace')[:200])

k = vals['kernel_size']; ps = vals['page_size']
print("\n内核在文件中的偏移: %#x, 长度: %d (%#x)" % (ps, k, k))
kern = d[ps:ps+k]
print("kernel 前 16 字节:", kern[:16].hex())
open('kernel_raw.bin','wb').write(kern)
print("已写出 kernel_raw.bin", len(kern))

# 检查是否未压缩
i = kern.find(b'Linux version 4.9.44')
print("'Linux version 4.9.44' 在 kernel_raw 中的偏移:", i)
