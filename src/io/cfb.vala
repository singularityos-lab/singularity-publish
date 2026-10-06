namespace Singularity.Apps.Publish {

    public class CfbEntry {
        public string name;
        public string path;
        public int type;
        public uint32 left;
        public uint32 right;
        public uint32 child;
        public uint32 start;
        public uint64 size;
    }

    public class CompoundFile {
        public const uint32 FREESECT = 0xFFFFFFFFU;
        public const uint32 ENDOFCHAIN = 0xFFFFFFFEU;
        public const uint32 FATSECT = 0xFFFFFFFDU;
        public const uint32 DIFSECT = 0xFFFFFFFCU;
        public const uint32 NOSTREAM = 0xFFFFFFFFU;

        private uint8[] data;
        public int sector_size = 512;
        public int mini_size = 64;
        public uint32 mini_cutoff = 4096;
        private uint32[] fat = {};
        private uint32[] minifat = {};
        private uint8[] ministream = {};
        public Gee.ArrayList<CfbEntry> entries = new Gee.ArrayList<CfbEntry> ();
        private Gee.HashMap<string, CfbEntry> by_path = new Gee.HashMap<string, CfbEntry> ();

        public static bool is_cfb (uint8[] d) {
            uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
            if (d.length < 8) return false;
            for (int i = 0; i < 8; i++) if (d[i] != sig[i]) return false;
            return true;
        }

        private uint16 u16 (int off) throws FormatError {
            if (off < 0 || off + 2 > data.length) throw new FormatError.INVALID (_("The compound file is truncated."));
            return (uint16) (data[off] | (data[off + 1] << 8));
        }

        private uint32 u32 (int off) throws FormatError {
            if (off < 0 || off + 4 > data.length) throw new FormatError.INVALID (_("The compound file is truncated."));
            return (uint32) data[off] | ((uint32) data[off + 1] << 8) | ((uint32) data[off + 2] << 16) | ((uint32) data[off + 3] << 24);
        }

        private int64 sector_offset (uint32 s) {
            return ((int64) s + 1) * sector_size;
        }

        public CompoundFile (uint8[] bytes) throws FormatError {
            data = bytes;
            if (!is_cfb (data)) throw new FormatError.INVALID (_("The file is not an OLE compound document."));
            if (data.length < 512) throw new FormatError.INVALID (_("The compound file is truncated."));
            uint16 shift = u16 (0x1E);
            uint16 mshift = u16 (0x20);
            if (shift != 9 && shift != 12) throw new FormatError.INVALID (_("The compound file has an unsupported sector size."));
            if (mshift != 6) throw new FormatError.INVALID (_("The compound file has an unsupported mini sector size."));
            sector_size = 1 << shift;
            mini_size = 1 << mshift;
            uint32 num_fat = u32 (0x2C);
            uint32 first_dir = u32 (0x30);
            mini_cutoff = u32 (0x38);
            if (mini_cutoff == 0) mini_cutoff = 4096;
            uint32 first_minifat = u32 (0x3C);
            uint32 num_minifat = u32 (0x40);
            uint32 first_difat = u32 (0x44);
            uint32 num_difat = u32 (0x48);
            int64 max_sectors = data.length / sector_size + 1;
            if (num_fat > max_sectors) throw new FormatError.INVALID (_("The compound file is truncated."));
            var fat_sectors = new Gee.ArrayList<uint32> ();
            for (int i = 0; i < 109 && fat_sectors.size < num_fat; i++) {
                uint32 s = u32 (0x4C + i * 4);
                if (s == FREESECT) break;
                fat_sectors.add (s);
            }
            uint32 dif = first_difat;
            int per = sector_size / 4 - 1;
            var seen_dif = new Gee.HashSet<uint32> ();
            uint32 dif_count = 0;
            while (fat_sectors.size < num_fat && dif != ENDOFCHAIN && dif != FREESECT) {
                if (seen_dif.contains (dif) || dif_count > num_difat + 1) throw new FormatError.INVALID (_("The compound file has a looping sector chain."));
                seen_dif.add (dif);
                dif_count++;
                int64 off = sector_offset (dif);
                if (off + sector_size > data.length) throw new FormatError.INVALID (_("The compound file is truncated."));
                for (int i = 0; i < per && fat_sectors.size < num_fat; i++) {
                    uint32 s = u32 ((int) off + i * 4);
                    if (s == FREESECT) continue;
                    fat_sectors.add (s);
                }
                dif = u32 ((int) off + per * 4);
            }
            int epp = sector_size / 4;
            var f = new uint32[fat_sectors.size * epp];
            for (int i = 0; i < fat_sectors.size; i++) {
                int64 off = sector_offset (fat_sectors[i]);
                if (off + sector_size > data.length) throw new FormatError.INVALID (_("The compound file is truncated."));
                for (int k = 0; k < epp; k++) f[i * epp + k] = u32 ((int) off + k * 4);
            }
            fat = f;
            var dir = read_chain (first_dir, -1);
            if (dir.length < 128) throw new FormatError.INVALID (_("The compound file has no directory."));
            parse_directory (dir);
            if (num_minifat > 0 && first_minifat != ENDOFCHAIN) {
                var mf = read_chain (first_minifat, -1);
                var m = new uint32[mf.length / 4];
                for (int i = 0; i < m.length; i++) m[i] = (uint32) mf[i * 4] | ((uint32) mf[i * 4 + 1] << 8) | ((uint32) mf[i * 4 + 2] << 16) | ((uint32) mf[i * 4 + 3] << 24);
                minifat = m;
            }
            var root = entries[0];
            if (root.start != ENDOFCHAIN && root.start != FREESECT && root.size > 0) ministream = read_chain (root.start, (int64) root.size);
        }

        public uint8[] read_chain (uint32 start, int64 size) throws FormatError {
            var buf = new ByteArray ();
            uint32 s = start;
            var visited = new bool[fat.length];
            while (s != ENDOFCHAIN) {
                if (s == FREESECT || s >= fat.length) throw new FormatError.INVALID (_("The compound file has a broken sector chain."));
                if (visited[s]) throw new FormatError.INVALID (_("The compound file has a looping sector chain."));
                visited[s] = true;
                int64 off = sector_offset (s);
                if (off + sector_size > data.length) {
                    if (size >= 0 && off < data.length && buf.len + (data.length - off) >= size) {
                        buf.append (data[(int) off:data.length]);
                        break;
                    }
                    throw new FormatError.INVALID (_("The compound file is truncated."));
                }
                buf.append (data[(int) off:(int) off + sector_size]);
                if (size >= 0 && buf.len >= size) break;
                s = fat[s];
            }
            if (size >= 0) {
                if (buf.len < size) throw new FormatError.INVALID (_("The compound file is truncated."));
                buf.set_size ((uint) size);
            }
            return buf.steal ();
        }

        private uint8[] read_mini (uint32 start, int64 size) throws FormatError {
            var buf = new ByteArray ();
            uint32 s = start;
            var visited = new bool[minifat.length];
            while (s != ENDOFCHAIN && buf.len < size) {
                if (s >= minifat.length) throw new FormatError.INVALID (_("The compound file has a broken mini sector chain."));
                if (visited[s]) throw new FormatError.INVALID (_("The compound file has a looping sector chain."));
                visited[s] = true;
                int64 off = (int64) s * mini_size;
                if (off + mini_size > ministream.length) throw new FormatError.INVALID (_("The compound file is truncated."));
                buf.append (ministream[(int) off:(int) off + mini_size]);
                s = minifat[s];
            }
            if (buf.len < size) throw new FormatError.INVALID (_("The compound file is truncated."));
            buf.set_size ((uint) size);
            return buf.steal ();
        }

        private void parse_directory (uint8[] dir) throws FormatError {
            int n = dir.length / 128;
            var raw = new Gee.ArrayList<CfbEntry> ();
            for (int i = 0; i < n; i++) {
                int o = i * 128;
                var e = new CfbEntry ();
                int nlen = dir[o + 64] | (dir[o + 65] << 8);
                var sb = new StringBuilder ();
                for (int k = 0; k + 1 < nlen && k < 64; k += 2) {
                    uint c = dir[o + k] | (dir[o + k + 1] << 8);
                    if (c == 0) break;
                    sb.append_unichar ((unichar) c);
                }
                e.name = sb.str;
                e.type = dir[o + 66];
                e.left = rd32 (dir, o + 68);
                e.right = rd32 (dir, o + 72);
                e.child = rd32 (dir, o + 76);
                e.start = rd32 (dir, o + 116);
                e.size = (uint64) rd32 (dir, o + 120);
                if (sector_size == 4096) e.size |= ((uint64) rd32 (dir, o + 124)) << 32;
                e.path = "";
                raw.add (e);
            }
            if (raw.size == 0 || raw[0].type != 5) throw new FormatError.INVALID (_("The compound file has no root entry."));
            entries = raw;
            var visited = new Gee.HashSet<uint32> ();
            visited.add (0);
            walk (raw[0].child, "", raw, visited, 0);
        }

        private static uint32 rd32 (uint8[] d, int o) {
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        private void walk (uint32 id, string prefix, Gee.ArrayList<CfbEntry> raw, Gee.HashSet<uint32> visited, int depth) throws FormatError {
            if (id == NOSTREAM) return;
            if (id >= (uint32) raw.size) throw new FormatError.INVALID (_("The compound file directory is damaged."));
            if (visited.contains (id)) throw new FormatError.INVALID (_("The compound file directory is damaged."));
            if (depth > 256) throw new FormatError.INVALID (_("The compound file directory is too deep."));
            visited.add (id);
            var e = raw[(int) id];
            walk (e.left, prefix, raw, visited, depth + 1);
            e.path = prefix == "" ? e.name : prefix + "/" + e.name;
            by_path[e.path.down ()] = e;
            if (e.type == 1) walk (e.child, e.path, raw, visited, depth + 1);
            walk (e.right, prefix, raw, visited, depth + 1);
        }

        public Gee.ArrayList<string> streams () {
            var l = new Gee.ArrayList<string> ();
            foreach (var e in entries) if (e.type == 2 && e.path != "") l.add (e.path);
            l.sort ();
            return l;
        }

        public bool has (string path) {
            var e = by_path[path.down ()];
            return e != null && e.type == 2;
        }

        public CfbEntry? entry (string path) {
            return by_path[path.down ()];
        }

        public uint8[] read (string path) throws FormatError {
            var e = by_path[path.down ()];
            if (e == null || e.type != 2) throw new FormatError.INVALID (_("The stream \"%s\" does not exist.").printf (path));
            if (e.size == 0) return new uint8[0];
            if (e.size > data.length) throw new FormatError.INVALID (_("The compound file is truncated."));
            if (e.size < mini_cutoff) return read_mini (e.start, (int64) e.size);
            return read_chain (e.start, (int64) e.size);
        }
    }
}
