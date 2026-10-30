import struct

ELF = 'vmlinux.elf'
BOOT = 'boot.img'
KERNEL_OFF_IN_BOOT = 0x800
KERNEL_SIZE = 15794688

d = open(ELF, 'rb').read()
e_shoff = struct.unpack_from('<Q', d, 0x28)[0]
e_shentsize = struct.unpack_from('<H', d, 0x3A)[0]
e_shnum = struct.unpack_from('<H', d, 0x3C)[0]
secs = []
for i in range(e_shnum):
    o = e_shoff + i * e_shentsize
    nm, typ, fl, addr, off, size, link, info, al, ent = struct.unpack_from('<IIQQQQIIQQ', d, o)
    secs.append((typ, addr, off, size, link, ent))

syms = {}
for typ, addr, off, size, link, ent in secs:
    if typ == 2:
        base = secs[link][2]
        cnt = size // 24
        for j in range(cnt):
            o = off + j * 24
            n, info, other, sh, val, sz = struct.unpack_from('<IBBHQQ', d, o)
            e = d.index(b'\0', base + n)
            s = d[base + n:e].decode('utf-8', 'replace')
            if s:
                syms.setdefault(s, val)

segs = []
e_phoff = struct.unpack_from('<Q', d, 0x20)[0]
e_phentsize = struct.unpack_from('<H', d, 0x36)[0]
e_phnum = struct.unpack_from('<H', d, 0x38)[0]
for i in range(e_phnum):
    o = e_phoff + i * e_phentsize
    t, fl, po, pv, pp, pf, pm, pa = struct.unpack_from('<IIQQQQQQ', d, o)
    if t == 1:
        segs.append((po, pv, pf))

def va2off(va):
    for po, pv, pf in segs:
        if pv <= va < pv + pf:
            return po + (va - pv)
    return None

print("可加载段:")
for po, pv, pf in segs[:5]:
    print("   file_off=%#x va=%#x size=%#x" % (po, pv, pf))

for name in ['cap_capable', 'security_capable', 'ns_capable', 'setuid']:
    v = syms.get(name)
    print("  %-20s %s" % (name, hex(v) if v else '未找到'))

target = 'cap_capable'
va = syms.get(target)
if va:
    foff_in_vmlinux = va2off(va)
    print("\n%s VA=%#x → vmlinux.elf 文件偏移=%#x" % (target, va, foff_in_vmlinux))
    orig = d[foff_in_vmlinux:foff_in_vmlinux + 16]
    print("vmlinux.elf 中的原始字节:", orig.hex())

    boot = open(BOOT, 'rb').read()
    boot_off = KERNEL_OFF_IN_BOOT + foff_in_vmlinux
    same = boot[boot_off:boot_off + 16]
    print("boot.img 中同偏移字节   :", same.hex())
    print("两者一致:", orig == same)
    print("boot.img 内绝对偏移 = %#x (内核内偏移 %#x)" % (boot_off, foff_in_vmlinux))
