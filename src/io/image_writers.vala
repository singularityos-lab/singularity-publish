namespace Singularity.Apps.Publish {

    public class ByteWriter {
        public ByteArray b = new ByteArray ();

        public void u8 (uint v) {
            uint8[] one = { (uint8) (v & 0xff) };
            b.append (one);
        }

        public void u16 (uint v) {
            u8 (v);
            u8 (v >> 8);
        }

        public void u32 (uint32 v) {
            u16 (v & 0xffff);
            u16 (v >> 16);
        }

        public void bytes (uint8[] d) {
            b.append (d);
        }

        public void ascii (string s) {
            b.append (s.data);
        }

        public uint len () {
            return b.len;
        }

        public void set_u32 (uint at, uint32 v) {
            b.data[at] = (uint8) (v & 0xff);
            b.data[at + 1] = (uint8) ((v >> 8) & 0xff);
            b.data[at + 2] = (uint8) ((v >> 16) & 0xff);
            b.data[at + 3] = (uint8) ((v >> 24) & 0xff);
        }

        public uint8[] steal () {
            return b.steal ();
        }
    }

    public class RasterPixels {
        public int width;
        public int height;
        public int channels;
        public uint8[] data;

        public static RasterPixels from_surface (Cairo.ImageSurface surf, bool keep_alpha) {
            surf.flush ();
            var p = new RasterPixels ();
            p.width = surf.get_width ();
            p.height = surf.get_height ();
            p.channels = keep_alpha ? 4 : 3;
            p.data = new uint8[p.width * p.height * p.channels];
            unowned uint8[] s = surf.get_data ();
            int stride = surf.get_stride ();
            bool le = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;
            bool has_alpha = surf.get_format () == Cairo.Format.ARGB32;
            for (int y = 0; y < p.height; y++) {
                for (int x = 0; x < p.width; x++) {
                    int si = y * stride + x * 4;
                    uint b = s[si + (le ? 0 : 3)], g = s[si + (le ? 1 : 2)], r = s[si + (le ? 2 : 1)], a = has_alpha ? s[si + (le ? 3 : 0)] : 255;
                    if (a > 0 && a < 255) {
                        r = uint.min (255, r * 255 / a);
                        g = uint.min (255, g * 255 / a);
                        b = uint.min (255, b * 255 / a);
                    }
                    if (!keep_alpha && a < 255) {
                        r = (r * a + 255 * (255 - a)) / 255;
                        g = (g * a + 255 * (255 - a)) / 255;
                        b = (b * a + 255 * (255 - a)) / 255;
                    }
                    int di = (y * p.width + x) * p.channels;
                    p.data[di] = (uint8) r;
                    p.data[di + 1] = (uint8) g;
                    p.data[di + 2] = (uint8) b;
                    if (keep_alpha) p.data[di + 3] = (uint8) a;
                }
            }
            return p;
        }
    }

    public class TiffWriter {
        private static void packbits_row (ByteWriter o, uint8[] d, int start, int len) {
            int i = 0;
            while (i < len) {
                int run = 1;
                while (i + run < len && run < 128 && d[start + i + run] == d[start + i]) run++;
                if (run >= 3) {
                    o.u8 ((uint) (257 - run));
                    o.u8 (d[start + i]);
                    i += run;
                    continue;
                }
                int lit = 0;
                while (i + lit < len && lit < 128) {
                    if (i + lit + 2 < len && d[start + i + lit] == d[start + i + lit + 1] && d[start + i + lit] == d[start + i + lit + 2]) break;
                    lit++;
                }
                if (lit == 0) lit = 1;
                o.u8 ((uint) (lit - 1));
                for (int k = 0; k < lit; k++) o.u8 (d[start + i + k]);
                i += lit;
            }
        }

        public static uint8[] encode (int width, int height, int channels, uint8[] pixels, bool cmyk, double dpi, bool compress = true) {
            var o = new ByteWriter ();
            o.ascii ("II");
            o.u16 (42);
            o.u32 (8);
            int ntags = cmyk ? 14 : 13;
            uint ifd_size = 2 + ntags * 12 + 4;
            uint extra = 8;
            uint bits_off = extra + ifd_size;
            uint xres_off = bits_off + (uint) (channels * 2);
            uint yres_off = xres_off + 8;
            uint data_off = yres_off + 8;
            int rows_per_strip = int.max (1, 16384 / int.max (1, width * channels));
            int strips = (height + rows_per_strip - 1) / rows_per_strip;
            uint offsets_off = data_off;
            uint counts_off = offsets_off + (uint) (strips * 4);
            uint strip_data = counts_off + (uint) (strips * 4);
            var strip_bytes = new Gee.ArrayList<Bytes> ();
            for (int s = 0; s < strips; s++) {
                var sw = new ByteWriter ();
                int y0 = s * rows_per_strip, y1 = int.min (height, y0 + rows_per_strip);
                for (int y = y0; y < y1; y++) {
                    int start = y * width * channels;
                    if (compress) packbits_row (sw, pixels, start, width * channels);
                    else sw.bytes (pixels[start:start + width * channels]);
                }
                strip_bytes.add (new Bytes.take (sw.steal ()));
            }
            o.u16 (ntags);
            tag (o, 256, 4, 1, (uint32) width);
            tag (o, 257, 4, 1, (uint32) height);
            tag (o, 258, 3, (uint32) channels, bits_off);
            tag (o, 259, 3, 1, compress ? 32773 : 1);
            tag (o, 262, 3, 1, cmyk ? 5 : 2);
            tag (o, 273, 4, (uint32) strips, strips == 1 ? strip_data : offsets_off);
            tag (o, 277, 3, 1, (uint32) channels);
            tag (o, 278, 4, 1, (uint32) rows_per_strip);
            uint32 first_count = strip_bytes.size > 0 ? (uint32) strip_bytes[0].get_size () : 0;
            tag (o, 279, 4, (uint32) strips, strips == 1 ? first_count : counts_off);
            tag (o, 282, 5, 1, xres_off);
            tag (o, 283, 5, 1, yres_off);
            tag (o, 284, 3, 1, 1);
            tag (o, 296, 3, 1, 2);
            if (cmyk) tag (o, 332, 3, 1, 1);
            o.u32 (0);
            for (int i = 0; i < channels; i++) o.u16 (8);
            uint32 res = (uint32) Math.round (dpi * 100);
            o.u32 (res);
            o.u32 (100);
            o.u32 (res);
            o.u32 (100);
            uint32 off = strip_data;
            for (int s = 0; s < strips; s++) {
                o.u32 (off);
                off += (uint32) strip_bytes[s].get_size ();
            }
            foreach (var sb in strip_bytes) o.u32 ((uint32) sb.get_size ());
            foreach (var sb in strip_bytes) o.bytes (sb.get_data ());
            return o.steal ();
        }

        private static void tag (ByteWriter o, uint id, uint type, uint32 count, uint32 val) {
            o.u16 (id);
            o.u16 (type);
            o.u32 (count);
            if (type == 3 && count == 1) {
                o.u16 (val);
                o.u16 (0);
            } else {
                o.u32 (val);
            }
        }
    }

    public class BmpWriter {
        public static uint8[] encode (RasterPixels p, double dpi) {
            int row = (p.width * 3 + 3) & ~3;
            uint32 size = 54 + (uint32) (row * p.height);
            var o = new ByteWriter ();
            o.ascii ("BM");
            o.u32 (size);
            o.u32 (0);
            o.u32 (54);
            o.u32 (40);
            o.u32 ((uint32) p.width);
            o.u32 ((uint32) p.height);
            o.u16 (1);
            o.u16 (24);
            o.u32 (0);
            o.u32 ((uint32) (row * p.height));
            uint32 ppm = (uint32) Math.round (dpi / 0.0254);
            o.u32 (ppm);
            o.u32 (ppm);
            o.u32 (0);
            o.u32 (0);
            var line = new uint8[row];
            for (int y = p.height - 1; y >= 0; y--) {
                for (int x = 0; x < p.width; x++) {
                    int i = (y * p.width + x) * p.channels;
                    line[x * 3] = p.data[i + 2];
                    line[x * 3 + 1] = p.data[i + 1];
                    line[x * 3 + 2] = p.data[i];
                }
                o.bytes (line);
            }
            return o.steal ();
        }
    }

    public class GifWriter {
        private class Box {
            public int[] idx;
            public int lo;
            public int hi;
        }

        private static uint8[] palette_median_cut (RasterPixels p, int colors, out int count) {
            int n = p.width * p.height;
            int step = int.max (1, n / 60000);
            var sample = new Gee.ArrayList<int> ();
            for (int i = 0; i < n; i += step) {
                if (p.channels == 4 && p.data[i * 4 + 3] < 128) continue;
                sample.add (i);
            }
            var pal = new uint8[colors * 3];
            if (sample.size == 0) {
                count = 1;
                return pal;
            }
            int[] all = sample.to_array ();
            var boxes = new Gee.ArrayList<Box> ();
            var b0 = new Box ();
            b0.idx = all;
            b0.lo = 0;
            b0.hi = all.length;
            boxes.add (b0);
            while (boxes.size < colors) {
                int best = -1, best_range = -1, best_ch = 0;
                for (int k = 0; k < boxes.size; k++) {
                    var bx = boxes[k];
                    if (bx.hi - bx.lo < 2) continue;
                    for (int ch = 0; ch < 3; ch++) {
                        int mn = 255, mx = 0;
                        for (int i = bx.lo; i < bx.hi; i++) {
                            int v = p.data[bx.idx[i] * p.channels + ch];
                            if (v < mn) mn = v;
                            if (v > mx) mx = v;
                        }
                        if (mx - mn > best_range) {
                            best_range = mx - mn;
                            best = k;
                            best_ch = ch;
                        }
                    }
                }
                if (best < 0 || best_range <= 0) break;
                var sel = boxes[best];
                int chn = best_ch;
                var slice = new Gee.ArrayList<int> ();
                for (int i = sel.lo; i < sel.hi; i++) slice.add (sel.idx[i]);
                slice.sort ((a, b) => p.data[a * p.channels + chn] - p.data[b * p.channels + chn]);
                for (int i = 0; i < slice.size; i++) sel.idx[sel.lo + i] = slice[i];
                int mid = sel.lo + (sel.hi - sel.lo) / 2;
                var nb = new Box ();
                nb.idx = sel.idx;
                nb.lo = mid;
                nb.hi = sel.hi;
                sel.hi = mid;
                boxes.add (nb);
            }
            count = boxes.size;
            for (int k = 0; k < boxes.size; k++) {
                var bx = boxes[k];
                long r = 0, g = 0, b = 0;
                int cnt = int.max (1, bx.hi - bx.lo);
                for (int i = bx.lo; i < bx.hi; i++) {
                    int o = bx.idx[i] * p.channels;
                    r += p.data[o];
                    g += p.data[o + 1];
                    b += p.data[o + 2];
                }
                pal[k * 3] = (uint8) (r / cnt);
                pal[k * 3 + 1] = (uint8) (g / cnt);
                pal[k * 3 + 2] = (uint8) (b / cnt);
            }
            return pal;
        }

        private class LzwOut {
            public ByteWriter o;
            private uint32 acc = 0;
            private int bits = 0;
            private uint8[] block = new uint8[255];
            private int fill = 0;

            public LzwOut (ByteWriter o) {
                this.o = o;
            }

            public void put (int code, int size) {
                acc |= ((uint32) code) << bits;
                bits += size;
                while (bits >= 8) {
                    push ((uint8) (acc & 0xff));
                    acc >>= 8;
                    bits -= 8;
                }
            }

            private void push (uint8 v) {
                block[fill++] = v;
                if (fill == 255) flush_block ();
            }

            private void flush_block () {
                if (fill == 0) return;
                o.u8 ((uint) fill);
                o.bytes (block[0:fill]);
                fill = 0;
            }

            public void finish () {
                if (bits > 0) push ((uint8) (acc & 0xff));
                acc = 0;
                bits = 0;
                flush_block ();
                o.u8 (0);
            }
        }

        private static void lzw (ByteWriter o, uint8[] indices, int min_size) {
            o.u8 ((uint) min_size);
            var out_bits = new LzwOut (o);
            int clear = 1 << min_size, eoi = clear + 1;
            var table = new Gee.HashMap<int, int> ();
            int next = eoi + 1;
            int size = min_size + 1;
            out_bits.put (clear, size);
            if (indices.length == 0) {
                out_bits.put (eoi, size);
                out_bits.finish ();
                return;
            }
            int prefix = indices[0];
            for (int i = 1; i < indices.length; i++) {
                int k = indices[i];
                int key = (prefix << 8) | k;
                if (table.has_key (key)) {
                    prefix = table[key];
                    continue;
                }
                out_bits.put (prefix, size);
                if (next < 4096) {
                    table[key] = next++;
                    if (next > (1 << size) && size < 12) size++;
                } else {
                    out_bits.put (clear, size);
                    table.clear ();
                    next = eoi + 1;
                    size = min_size + 1;
                }
                prefix = k;
            }
            out_bits.put (prefix, size);
            out_bits.put (eoi, size);
            out_bits.finish ();
        }

        public static uint8[] encode (RasterPixels p, bool transparent) {
            bool alpha = transparent && p.channels == 4;
            int count;
            var pal = palette_median_cut (p, alpha ? 255 : 256, out count);
            int tindex = alpha ? count : -1;
            int total = alpha ? count + 1 : count;
            int bits = 1;
            while ((1 << bits) < total) bits++;
            int table_size = 1 << bits;
            var lut = new int[32768];
            for (int i = 0; i < lut.length; i++) lut[i] = -1;
            var indices = new uint8[p.width * p.height];
            for (int i = 0; i < p.width * p.height; i++) {
                int o = i * p.channels;
                if (alpha && p.data[o + 3] < 128) {
                    indices[i] = (uint8) tindex;
                    continue;
                }
                int key = ((p.data[o] >> 3) << 10) | ((p.data[o + 1] >> 3) << 5) | (p.data[o + 2] >> 3);
                if (lut[key] < 0) {
                    int best = 0, bd = int.MAX;
                    for (int k = 0; k < count; k++) {
                        int dr = pal[k * 3] - p.data[o], dg = pal[k * 3 + 1] - p.data[o + 1], db = pal[k * 3 + 2] - p.data[o + 2];
                        int d = dr * dr * 3 + dg * dg * 4 + db * db * 2;
                        if (d < bd) {
                            bd = d;
                            best = k;
                        }
                    }
                    lut[key] = best;
                }
                indices[i] = (uint8) lut[key];
            }
            var w = new ByteWriter ();
            w.ascii ("GIF89a");
            w.u16 (p.width);
            w.u16 (p.height);
            w.u8 (0x80 | 0x70 | (bits - 1));
            w.u8 (0);
            w.u8 (0);
            for (int k = 0; k < table_size; k++) {
                if (k < count) {
                    w.u8 (pal[k * 3]);
                    w.u8 (pal[k * 3 + 1]);
                    w.u8 (pal[k * 3 + 2]);
                } else {
                    w.u8 (255);
                    w.u8 (255);
                    w.u8 (255);
                }
            }
            if (alpha) {
                w.u8 (0x21);
                w.u8 (0xF9);
                w.u8 (4);
                w.u8 (1);
                w.u16 (0);
                w.u8 ((uint) tindex);
                w.u8 (0);
            }
            w.u8 (0x2C);
            w.u16 (0);
            w.u16 (0);
            w.u16 (p.width);
            w.u16 (p.height);
            w.u8 (0);
            lzw (w, indices, int.max (2, bits));
            w.u8 (0x3B);
            return w.steal ();
        }
    }

    public class ImageExport {
        public static string extension (string format) {
            switch (format) {
                case "jpeg": return "jpg";
                case "tiff": return "tif";
                case "gif": return "gif";
                case "bmp": return "bmp";
                default: return "png";
            }
        }

        public static uint8[] encode (Cairo.ImageSurface surf, string format, ExportOptions opts, ColorManager? cm) {
            switch (format) {
                case "tiff":
                    if (opts.image_cmyk && cm != null) {
                        var cmyk = cm.surface_to_cmyk (surf);
                        return TiffWriter.encode (surf.get_width (), surf.get_height (), 4, cmyk, true, opts.dpi);
                    }
                    var rgb = RasterPixels.from_surface (surf, false);
                    return TiffWriter.encode (rgb.width, rgb.height, 3, rgb.data, false, opts.dpi);
                case "gif":
                    return GifWriter.encode (RasterPixels.from_surface (surf, opts.transparent), opts.transparent);
                default:
                    return BmpWriter.encode (RasterPixels.from_surface (surf, false), opts.dpi);
            }
        }

        public static Gee.ArrayList<string> export (Exporter ex, string dir, string base_name, string format) throws Error {
            var out_files = new Gee.ArrayList<string> ();
            var list = ex.sheets ();
            var cm = ColorManager.for_settings (ex.pub.settings);
            string ext = extension (format);
            for (int i = 0; i < list.size; i++) {
                var sh = list[i];
                var surf = ex.render_sheet (sh);
                string label = sh.slots.size == 1 && ex.opts.impose == ImposeMode.NONE ? ex.pub.page_label (sh.slots[0].page) : (i + 1).to_string ();
                string name = list.size == 1 ? "%s.%s".printf (base_name, ext) : "%s-%s.%s".printf (base_name, label, ext);
                string p = Path.build_filename (dir, name);
                FileUtils.set_data (p, encode (surf, format, ex.opts, cm));
                out_files.add (p);
            }
            return out_files;
        }
    }
}
