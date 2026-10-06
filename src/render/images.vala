namespace Singularity.Apps.Publish {

    public enum LinkStatus {
        EMBEDDED,
        OK,
        MODIFIED,
        MISSING,
        EMPTY
    }

    public class ImageInfo {
        public Cairo.ImageSurface? surface = null;
        public int width = 0;
        public int height = 0;
        public double dpi = 72;
        public bool has_alpha = false;
        public int components = 3;
        public string format = "";
        public bool vector = false;
    }

    public class Placement {
        public double ox;
        public double oy;
        public double sx;
        public double sy;

        public double ppi_x () {
            return sx > 0 ? 72.0 / sx : 0;
        }

        public double ppi_y () {
            return sy > 0 ? 72.0 / sy : 0;
        }
    }

    public class ImageStore {
        private static ImageStore? instance = null;
        private Gee.HashMap<string, ImageInfo> cache = new Gee.HashMap<string, ImageInfo> ();

        public static ImageStore get_default () {
            if (instance == null) instance = new ImageStore ();
            return instance;
        }

        public void clear () {
            cache.clear ();
            masks.clear ();
            path_cache.clear ();
            vectors.clear ();
        }

        public static string resolve_link (Publication pub, string link) {
            if (link == "") return "";
            if (Path.is_absolute (link)) {
                if (FileUtils.test (link, FileTest.EXISTS) || pub.base_dir == "") return link;
                string alt = Path.build_filename (pub.base_dir, Path.get_basename (link));
                if (FileUtils.test (alt, FileTest.EXISTS)) return alt;
                return link;
            }
            if (pub.base_dir != "") return Path.build_filename (pub.base_dir, link);
            return link;
        }

        public static string stamp_for (string path) {
            try {
                var info = File.new_for_path (path).query_info ("standard::size,time::modified", FileQueryInfoFlags.NONE);
                return "%lld:%llu".printf (info.get_size (), info.get_attribute_uint64 ("time::modified"));
            } catch (Error e) {
                return "";
            }
        }

        public static LinkStatus status (Publication pub, ImageFrame f) {
            if (f.media != "" && f.link == "") return LinkStatus.EMBEDDED;
            if (f.link == "") return f.media != "" ? LinkStatus.EMBEDDED : LinkStatus.EMPTY;
            string p = resolve_link (pub, f.link);
            if (!FileUtils.test (p, FileTest.IS_REGULAR)) return f.media != "" ? LinkStatus.MISSING : LinkStatus.MISSING;
            if (f.link_stamp != "" && stamp_for (p) != f.link_stamp) return LinkStatus.MODIFIED;
            return LinkStatus.OK;
        }

        public static string status_label (LinkStatus s) {
            switch (s) {
                case LinkStatus.EMBEDDED: return _("Embedded");
                case LinkStatus.MODIFIED: return _("Modified");
                case LinkStatus.MISSING: return _("Missing");
                case LinkStatus.EMPTY: return _("Empty");
                default: return _("Linked");
            }
        }

        public uint8[]? bytes_for (Publication pub, ImageFrame f) {
            if (f.link != "") {
                string p = resolve_link (pub, f.link);
                if (FileUtils.test (p, FileTest.IS_REGULAR)) {
                    try {
                        uint8[] data;
                        FileUtils.get_data (p, out data);
                        return data;
                    } catch (Error e) {
                    }
                }
            }
            if (f.media != "" && pub.media.has_key (f.media)) return pub.media[f.media].get_data ();
            return null;
        }

        public ImageInfo? info (Publication pub, ImageFrame f) {
            string key;
            if (f.link != "") {
                string p = resolve_link (pub, f.link);
                if (FileUtils.test (p, FileTest.IS_REGULAR)) key = "file:" + p + ":" + stamp_for (p);
                else if (f.media != "") key = "media:" + f.media;
                else return null;
            } else if (f.media != "") {
                key = "media:" + f.media;
            } else {
                return null;
            }
            if (f.pdf_page > 0) key += ":p%d".printf (f.pdf_page);
            if (cache.has_key (key)) return cache[key];
            var data = bytes_for (pub, f);
            ImageInfo? inf = data != null ? decode (data, f.pdf_page) : null;
            if (inf != null) cache[key] = inf;
            return inf;
        }

        public static int jpeg_components (uint8[] d) {
            if (d.length < 4 || d[0] != 0xFF || d[1] != 0xD8) return 0;
            int i = 2;
            while (i + 9 < d.length) {
                if (d[i] != 0xFF) {
                    i++;
                    continue;
                }
                uint8 m = d[i + 1];
                if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
                    i += 2;
                    continue;
                }
                int len = (d[i + 2] << 8) | d[i + 3];
                if ((m >= 0xC0 && m <= 0xC3) || (m >= 0xC5 && m <= 0xC7) || (m >= 0xC9 && m <= 0xCB) || (m >= 0xCD && m <= 0xCF)) {
                    return d[i + 9];
                }
                i += 2 + len;
            }
            return 0;
        }

        public static string sniff (uint8[] d) {
            if (d.length >= 8 && d[0] == 0x89 && d[1] == 'P' && d[2] == 'N' && d[3] == 'G') return "png";
            if (d.length >= 3 && d[0] == 0xFF && d[1] == 0xD8) return "jpeg";
            if (d.length >= 6 && d[0] == 'G' && d[1] == 'I' && d[2] == 'F') return "gif";
            if (d.length >= 12 && d[0] == 'R' && d[1] == 'I' && d[2] == 'F' && d[3] == 'F' && d[8] == 'W') return "webp";
            if (d.length >= 2 && d[0] == 'B' && d[1] == 'M') return "bmp";
            if (d.length >= 4 && ((d[0] == 'I' && d[1] == 'I') || (d[0] == 'M' && d[1] == 'M'))) return "tiff";
            if (d.length >= 5 && d[0] == '%' && d[1] == 'P' && d[2] == 'D' && d[3] == 'F') return "pdf";
            string head = Bin.head (d, 512);
            if (head.contains ("<svg") || head.has_prefix ("<?xml")) return "svg";
            return "";
        }

        private Gee.HashMap<string, VectorArt?> vectors = new Gee.HashMap<string, VectorArt?> ();

        public VectorArt? vector (Publication pub, ImageFrame f) {
            string key = f.link != "" ? resolve_link (pub, f.link) + ":" + stamp_for (resolve_link (pub, f.link)) : "media:" + f.media;
            if (vectors.has_key (key)) return vectors[key];
            var data = bytes_for (pub, f);
            VectorArt? v = null;
            if (data != null) {
                string kind = sniff (data);
                if (kind == "svg" || kind == "pdf" || kind == "") v = VectorArt.load (data);
            }
            vectors[key] = v;
            return v;
        }

        private static ImageInfo? decode_vector (uint8[] data, int page) {
            var v = VectorArt.load (data);
            if (v == null) return null;
            var info = new ImageInfo ();
            info.format = v.kind;
            info.vector = true;
            double scale = 300.0 / 72.0;
            info.surface = v.raster (page, scale);
            info.width = info.surface.get_width ();
            info.height = info.surface.get_height ();
            info.dpi = 300;
            info.has_alpha = v.kind != "pdf";
            return info;
        }

        public static ImageInfo? decode (uint8[] data, int page = 0) {
            string kind0 = sniff (data);
            if (kind0 == "pdf" || kind0 == "" || kind0 == "svg") {
                var vi = decode_vector (data, page);
                if (vi != null) return vi;
            }
            var info = new ImageInfo ();
            info.format = sniff (data);
            info.vector = info.format == "svg";
            if (info.format == "jpeg") info.components = jpeg_components (data);
            try {
                var loader = new Gdk.PixbufLoader ();
                loader.write (data);
                loader.close ();
                var pb = loader.get_pixbuf ();
                if (pb == null) return null;
                string? xd = pb.get_option ("x-dpi");
                if (xd != null) {
                    double v = double.parse (xd);
                    if (v > 1) info.dpi = v;
                }
                var rotated = pb.apply_embedded_orientation ();
                if (rotated != null) pb = rotated;
                info.width = pb.width;
                info.height = pb.height;
                info.has_alpha = pb.has_alpha;
                info.surface = to_surface (pb);
                return info;
            } catch (Error e) {
                return null;
            }
        }

        public static Cairo.ImageSurface to_surface (Gdk.Pixbuf pb) {
            int w = pb.width, h = pb.height;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            surf.flush ();
            unowned uint8[] src = pb.get_pixels_with_length ();
            unowned uint8[] dst = surf.get_data ();
            int ss = pb.rowstride, ds = surf.get_stride ();
            int nc = pb.n_channels;
            bool alpha = pb.has_alpha;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int si = y * ss + x * nc;
                    int di = y * ds + x * 4;
                    uint a = alpha ? src[si + 3] : 255;
                    uint r = src[si], g = src[si + 1], b = src[si + 2];
                    if (a < 255) {
                        r = r * a / 255;
                        g = g * a / 255;
                        b = b * a / 255;
                    }
                    if (GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN) {
                        dst[di] = (uint8) b;
                        dst[di + 1] = (uint8) g;
                        dst[di + 2] = (uint8) r;
                        dst[di + 3] = (uint8) a;
                    } else {
                        dst[di] = (uint8) a;
                        dst[di + 1] = (uint8) r;
                        dst[di + 2] = (uint8) g;
                        dst[di + 3] = (uint8) b;
                    }
                }
            }
            surf.mark_dirty ();
            return surf;
        }

        public static Placement place (ImageFrame f, ImageInfo info) {
            var p = new Placement ();
            double iw = double.max (1, info.width), ih = double.max (1, info.height);
            double natural = 72.0 / (info.dpi > 1 ? info.dpi : 72);
            switch (f.fit) {
                case FitMode.FIT:
                    double s = double.min (f.w / iw, f.h / ih);
                    p.sx = p.sy = s;
                    p.ox = (f.w - iw * s) * f.focus_x;
                    p.oy = (f.h - ih * s) * f.focus_y;
                    break;
                case FitMode.STRETCH:
                    p.sx = f.w / iw;
                    p.sy = f.h / ih;
                    p.ox = 0;
                    p.oy = 0;
                    break;
                case FitMode.MANUAL:
                    p.sx = p.sy = natural * f.img_scale;
                    p.ox = f.img_x;
                    p.oy = f.img_y;
                    break;
                default:
                    double s = double.max (f.w / iw, f.h / ih);
                    p.sx = p.sy = s;
                    p.ox = (f.w - iw * s) * f.focus_x;
                    p.oy = (f.h - ih * s) * f.focus_y;
                    break;
            }
            return p;
        }

        public static void to_manual (ImageFrame f, ImageInfo info) {
            var p = place (f, info);
            double natural = 72.0 / (info.dpi > 1 ? info.dpi : 72);
            f.img_scale = p.sx / natural;
            f.img_x = p.ox;
            f.img_y = p.oy;
            f.fit = FitMode.MANUAL;
        }

        public const int CONTOUR_AUTO = 0;
        public const int CONTOUR_EDGES = 1;
        public const int CONTOUR_PATH = 2;
        public const int CONTOUR_FRAME = 3;

        private Gee.HashMap<string, Cairo.ImageSurface> masks = new Gee.HashMap<string, Cairo.ImageSurface> ();

        private Gee.HashMap<string, PhotoshopPaths?> path_cache = new Gee.HashMap<string, PhotoshopPaths?> ();

        public PhotoshopPaths? image_paths (Publication pub, ImageFrame f) {
            string key = f.link != "" ? resolve_link (pub, f.link) + ":" + stamp_for (resolve_link (pub, f.link)) : "media:" + f.media;
            if (path_cache.has_key (key)) return path_cache[key];
            var data = bytes_for (pub, f);
            var found = data != null ? PhotoshopPaths.read (data) : null;
            path_cache[key] = found;
            return found;
        }

        public Cairo.ImageSurface? contour_mask (Publication pub, ImageFrame f, ImageInfo inf) {
            int src = f.contour_source;
            if (src == CONTOUR_FRAME) return null;
            if (src == CONTOUR_AUTO && inf.has_alpha) return inf.surface;
            string key = "%s:%d:%d".printf (f.link != "" ? resolve_link (pub, f.link) + ":" + stamp_for (resolve_link (pub, f.link)) : f.media, src, inf.width);
            if (masks.has_key (key)) return masks[key];
            Cairo.ImageSurface? mask = null;
            if (src == CONTOUR_AUTO || src == CONTOUR_PATH) {
                var paths = image_paths (pub, f);
                var path = paths != null ? paths.preferred () : null;
                if (path != null) {
                    mask = new Cairo.ImageSurface (Cairo.Format.ARGB32, inf.width, inf.height);
                    var cr = new Cairo.Context (mask);
                    cr.set_fill_rule (Cairo.FillRule.WINDING);
                    path.trace (cr, inf.width, inf.height);
                    cr.set_source_rgba (0, 0, 0, 1);
                    cr.fill ();
                    mask.flush ();
                }
            } else if (src == CONTOUR_EDGES) {
                mask = detect_edges (inf);
            }
            if (mask != null) masks[key] = mask;
            return mask;
        }

        public static Cairo.ImageSurface? detect_edges (ImageInfo inf, int threshold = 40) {
            if (inf.surface == null || inf.width < 2 || inf.height < 2) return null;
            var surf = inf.surface;
            surf.flush ();
            unowned uint8[] d = surf.get_data ();
            int stride = surf.get_stride ();
            int[] corners = { 0, (inf.width - 1) * 4, (inf.height - 1) * stride, (inf.height - 1) * stride + (inf.width - 1) * 4 };
            double br = 0, bg = 0, bb = 0, ba = 0;
            foreach (int c in corners) {
                bb += d[c];
                bg += d[c + 1];
                br += d[c + 2];
                ba += d[c + 3];
            }
            br /= 4;
            bg /= 4;
            bb /= 4;
            ba /= 4;
            var mask = new Cairo.ImageSurface (Cairo.Format.ARGB32, inf.width, inf.height);
            mask.flush ();
            unowned uint8[] m = mask.get_data ();
            int ms = mask.get_stride ();
            int aoff = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN ? 3 : 0;
            for (int y = 0; y < inf.height; y++) {
                for (int x = 0; x < inf.width; x++) {
                    int i = y * stride + x * 4;
                    double dist = Math.fabs (d[i] - bb) + Math.fabs (d[i + 1] - bg) + Math.fabs (d[i + 2] - br) + Math.fabs (d[i + 3] - ba);
                    m[y * ms + x * 4 + aoff] = dist > threshold ? 255 : 0;
                }
            }
            mask.mark_dirty ();
            return mask;
        }

        public Gee.ArrayList<double?>? alpha_rows (Publication pub, ImageFrame f, out double y0, out double step) {
            y0 = f.y;
            step = 2;
            var inf = info (pub, f);
            if (inf == null || inf.surface == null) return null;
            var pl = place (f, inf);
            var surf = contour_mask (pub, f, inf);
            if (surf == null) return null;
            surf.flush ();
            unowned uint8[] data = surf.get_data ();
            int stride = surf.get_stride ();
            int aoff = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN ? 3 : 0;
            int rows = (int) Math.ceil (f.h / step);
            var list = new Gee.ArrayList<double?> ();
            int px_step = int.max (1, (int) (inf.width / 400));
            for (int r = 0; r < rows; r++) {
                double ly0 = r * step, ly1 = ly0 + step;
                int vy0 = ((int) Math.floor ((ly0 - pl.oy) / pl.sy)).clamp (0, inf.height - 1);
                int vy1 = ((int) Math.ceil ((ly1 - pl.oy) / pl.sy)).clamp (0, inf.height - 1);
                int minx = int.MAX, maxx = -1;
                if ((ly1 - pl.oy) / pl.sy >= 0 && (ly0 - pl.oy) / pl.sy <= inf.height) {
                    for (int vy = vy0; vy <= vy1; vy += int.max (1, (vy1 - vy0) / 3 + 1)) {
                        int row = vy * stride;
                        for (int x = 0; x < inf.width; x += px_step) {
                            if (data[row + x * 4 + aoff] > 100) {
                                minx = int.min (minx, x);
                                break;
                            }
                        }
                        for (int x = inf.width - 1; x >= 0; x -= px_step) {
                            if (data[row + x * 4 + aoff] > 100) {
                                maxx = int.max (maxx, x);
                                break;
                            }
                        }
                    }
                }
                if (maxx < 0) {
                    list.add (null);
                    list.add (null);
                } else {
                    double lx0 = (pl.ox + minx * pl.sx).clamp (0, f.w), lx1 = (pl.ox + (maxx + 1) * pl.sx).clamp (0, f.w);
                    list.add (f.x + lx0);
                    list.add (f.x + lx1);
                }
            }
            return list;
        }
    }
}
