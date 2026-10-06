namespace Singularity.Apps.Publish {

    public class IccProfileInfo {
        public string path;
        public string description;
        public bool cmyk;

        public IccProfileInfo (string path, string description, bool cmyk) {
            this.path = path;
            this.description = description;
            this.cmyk = cmyk;
        }
    }

    public class ColorManager {
        public const string GENERIC_NAME = "Generic CMYK (Publish)";
        private static Gee.HashMap<string, ColorManager>? cache = null;
        public string path = "";
        public int intent = 1;
        private string desc = GENERIC_NAME;
        private uint8[] data = new uint8[0];
        private Gee.HashMap<string, Rgba?> proof_cache = new Gee.HashMap<string, Rgba?> ();
#if HAVE_LCMS
        private Lcms.Profile? cmyk_profile = null;
        private Lcms.Profile srgb_profile;
        private Lcms.Transform? to_cmyk = null;
        private Lcms.Transform? to_rgb = null;
        private Lcms.Transform? to_cmyk8 = null;
#endif

        public static ColorManager for_settings (DocSettings s) {
            return get (s.icc_profile, s.intent);
        }

        public static ColorManager get (string profile_path, int intent) {
            if (cache == null) cache = new Gee.HashMap<string, ColorManager> ();
            string key = "%s|%d".printf (profile_path, intent);
            if (!cache.has_key (key)) cache[key] = new ColorManager (profile_path, intent);
            return cache[key];
        }

        public ColorManager (string profile_path = "", int intent = 1) {
            this.intent = intent.clamp (0, 3);
#if HAVE_LCMS
            srgb_profile = Lcms.Profile.srgb ();
            if (profile_path != "") {
                try {
                    uint8[] bytes;
                    FileUtils.get_data (profile_path, out bytes);
                    var p = Lcms.Profile.from_mem (bytes);
                    if (p != null && p.color_space () == Lcms.SIG_CMYK_DATA) {
                        string d = profile_description (p);
                        cmyk_profile = (owned) p;
                        data = bytes;
                        path = profile_path;
                        desc = d != "" ? d : Path.get_basename (profile_path);
                    }
                } catch (Error e) {
                }
            }
            if (cmyk_profile == null) {
                cmyk_profile = generic_profile ();
                uint32 n = 0;
                cmyk_profile.save_to_mem (null, ref n);
                data = new uint8[n];
                cmyk_profile.save_to_mem (data, ref n);
            }
            uint32 flags = this.intent == 1 ? Lcms.FLAGS_BLACKPOINTCOMPENSATION : 0;
            to_cmyk = Lcms.Transform.create (srgb_profile, Lcms.TYPE_RGB_DBL, cmyk_profile, Lcms.TYPE_CMYK_DBL, this.intent, flags | Lcms.FLAGS_NOCACHE);
            to_rgb = Lcms.Transform.create (cmyk_profile, Lcms.TYPE_CMYK_DBL, srgb_profile, Lcms.TYPE_RGB_DBL, this.intent, flags | Lcms.FLAGS_NOCACHE);
            to_cmyk8 = Lcms.Transform.create (srgb_profile, Lcms.TYPE_RGB_8, cmyk_profile, Lcms.TYPE_CMYK_8, this.intent, flags);
#else
            data = generic_profile_bytes ();
#endif
        }

        public bool has_icc () {
            return path != "";
        }

        public bool color_managed () {
#if HAVE_LCMS
            return true;
#else
            return false;
#endif
        }

        public string description () {
            return desc;
        }

        public uint8[] profile_data () {
            return data;
        }

        public string output_condition () {
            return path != "" ? desc : "Custom";
        }

        public void rgb_to_cmyk (double r, double g, double b, out double c, out double m, out double y, out double k) {
#if HAVE_LCMS
            if (to_cmyk != null) {
                double[] i = { r.clamp (0, 1), g.clamp (0, 1), b.clamp (0, 1) };
                double[] o = new double[4];
                to_cmyk.apply (i, o, 1);
                c = (o[0] / 100).clamp (0, 1);
                m = (o[1] / 100).clamp (0, 1);
                y = (o[2] / 100).clamp (0, 1);
                k = (o[3] / 100).clamp (0, 1);
                return;
            }
#endif
            ColorMath.rgb_to_cmyk (r, g, b, out c, out m, out y, out k);
        }

        public Rgba cmyk_to_rgb (double c, double m, double y, double k) {
#if HAVE_LCMS
            if (to_rgb != null) {
                string key = "%.4f,%.4f,%.4f,%.4f".printf (c, m, y, k);
                if (proof_cache.has_key (key)) return proof_cache[key];
                double[] i = { c.clamp (0, 1) * 100, m.clamp (0, 1) * 100, y.clamp (0, 1) * 100, k.clamp (0, 1) * 100 };
                double[] o = new double[3];
                to_rgb.apply (i, o, 1);
                var v = Rgba (o[0].clamp (0, 1), o[1].clamp (0, 1), o[2].clamp (0, 1), 1);
                if (proof_cache.size > 4096) proof_cache.clear ();
                proof_cache[key] = v;
                return v;
            }
#endif
            return ColorMath.cmyk_to_rgb (c, m, y, k);
        }

        public uint8[] rgb8_to_cmyk8 (uint8[] rgb, int pixels) {
            var out_data = new uint8[pixels * 4];
#if HAVE_LCMS
            if (to_cmyk8 != null) {
                to_cmyk8.apply (rgb, out_data, pixels);
                return out_data;
            }
#endif
            for (int i = 0; i < pixels; i++) {
                double c, m, y, k;
                ColorMath.rgb_to_cmyk (rgb[i * 3] / 255.0, rgb[i * 3 + 1] / 255.0, rgb[i * 3 + 2] / 255.0, out c, out m, out y, out k);
                out_data[i * 4] = (uint8) Math.round (c * 255);
                out_data[i * 4 + 1] = (uint8) Math.round (m * 255);
                out_data[i * 4 + 2] = (uint8) Math.round (y * 255);
                out_data[i * 4 + 3] = (uint8) Math.round (k * 255);
            }
            return out_data;
        }

        public uint8[] surface_to_cmyk (Cairo.ImageSurface surf) {
            surf.flush ();
            int w = surf.get_width (), h = surf.get_height (), stride = surf.get_stride ();
            unowned uint8[] d = surf.get_data ();
            var rgb = new uint8[w * h * 3];
            bool le = GLib.ByteOrder.HOST == GLib.ByteOrder.LITTLE_ENDIAN;
            bool has_alpha = surf.get_format () == Cairo.Format.ARGB32;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int si = y * stride + x * 4, di = (y * w + x) * 3;
                    uint b = d[si + (le ? 0 : 3)], g = d[si + (le ? 1 : 2)], r = d[si + (le ? 2 : 1)], a = has_alpha ? d[si + (le ? 3 : 0)] : 255;
                    if (a > 0 && a < 255) {
                        r = uint.min (255, r * 255 / a);
                        g = uint.min (255, g * 255 / a);
                        b = uint.min (255, b * 255 / a);
                    } else if (a == 0) {
                        r = g = b = 255;
                    }
                    rgb[di] = (uint8) r;
                    rgb[di + 1] = (uint8) g;
                    rgb[di + 2] = (uint8) b;
                }
            }
            return rgb8_to_cmyk8 (rgb, w * h);
        }

        private static string[] profile_dirs () {
            var l = new Gee.ArrayList<string> ();
            l.add (Path.build_filename (Environment.get_user_data_dir (), "color", "icc"));
            l.add (Path.build_filename (Environment.get_user_data_dir (), "icc"));
            l.add (Path.build_filename (Environment.get_home_dir (), ".color", "icc"));
            foreach (string d in Environment.get_system_data_dirs ()) l.add (Path.build_filename (d, "color", "icc"));
            string? extra = Environment.get_variable ("PUBLISH_ICC_PATH");
            if (extra != null) foreach (string d in extra.split (":")) if (d != "") l.add (d);
            return l.to_array ();
        }

        private static void scan (string dir, Gee.ArrayList<IccProfileInfo> list, Gee.HashSet<string> seen, int depth) {
            if (depth > 3) return;
            try {
                var d = Dir.open (dir);
                string? n;
                while ((n = d.read_name ()) != null) {
                    string p = Path.build_filename (dir, n);
                    if (FileUtils.test (p, FileTest.IS_DIR)) {
                        scan (p, list, seen, depth + 1);
                        continue;
                    }
                    string low = n.down ();
                    if (!low.has_suffix (".icc") && !low.has_suffix (".icm")) continue;
                    var info = inspect (p);
                    if (info == null) continue;
                    if (seen.contains (p)) continue;
                    seen.add (p);
                    list.add (info);
                }
            } catch (FileError e) {
            }
        }

        public static IccProfileInfo? inspect (string path) {
            uint8[] head;
            try {
                FileUtils.get_data (path, out head);
            } catch (Error e) {
                return null;
            }
            if (head.length < 132 || head[36] != 'a' || head[37] != 'c' || head[38] != 's' || head[39] != 'p') return null;
            bool cmyk = head[16] == 'C' && head[17] == 'M' && head[18] == 'Y' && head[19] == 'K';
            string desc = Path.get_basename (path);
#if HAVE_LCMS
            var p = Lcms.Profile.from_mem (head);
            if (p != null) {
                string d = profile_description (p);
                if (d != "") desc = d;
            }
#endif
            return new IccProfileInfo (path, desc, cmyk);
        }

        public static Gee.ArrayList<IccProfileInfo> available_profiles () {
            var list = new Gee.ArrayList<IccProfileInfo> ();
            var seen = new Gee.HashSet<string> ();
            foreach (string d in profile_dirs ()) scan (d, list, seen, 0);
            list.sort ((a, b) => a.description.collate (b.description));
            return list;
        }

        public static Gee.ArrayList<IccProfileInfo> cmyk_profiles () {
            var list = new Gee.ArrayList<IccProfileInfo> ();
            foreach (var p in available_profiles ()) if (p.cmyk) list.add (p);
            return list;
        }

        private const double[] SRGB_TO_XYZ_D50 = { 0.4360747, 0.3850649, 0.1430804, 0.2225045, 0.7168786, 0.0606169, 0.0139322, 0.0971045, 0.7141733 };
        private const double[] XYZ_D50_TO_SRGB = { 3.1338561, -1.6168667, -0.4906146, -0.9787684, 1.9161415, 0.0334540, 0.0719453, -0.2289914, 1.4052427 };
        private const double WX = 0.9642;
        private const double WY = 1.0;
        private const double WZ = 0.8249;

        private static double lin (double v) {
            return v <= 0.04045 ? v / 12.92 : Math.pow ((v + 0.055) / 1.055, 2.4);
        }

        private static double gam (double v) {
            v = v.clamp (0, 1);
            return v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow (v, 1 / 2.4) - 0.055;
        }

        private static double f_lab (double t) {
            return t > 216.0 / 24389.0 ? Math.cbrt (t) : (24389.0 / 27.0 * t + 16) / 116;
        }

        private static double f_inv (double t) {
            double t3 = t * t * t;
            return t3 > 216.0 / 24389.0 ? t3 : (116 * t - 16) / (24389.0 / 27.0);
        }

        public static void rgb_to_lab (double r, double g, double b, out double l, out double a, out double bb) {
            double lr = lin (r), lg = lin (g), lb = lin (b);
            var m = SRGB_TO_XYZ_D50;
            double x = m[0] * lr + m[1] * lg + m[2] * lb;
            double y = m[3] * lr + m[4] * lg + m[5] * lb;
            double z = m[6] * lr + m[7] * lg + m[8] * lb;
            double fx = f_lab (x / WX), fy = f_lab (y / WY), fz = f_lab (z / WZ);
            l = 116 * fy - 16;
            a = 500 * (fx - fy);
            bb = 200 * (fy - fz);
        }

        public static void lab_to_rgb (double l, double a, double bb, out double r, out double g, out double b) {
            double fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - bb / 200;
            double x = f_inv (fx) * WX, y = (l > 8 ? fy * fy * fy : l / (24389.0 / 27.0)) * WY, z = f_inv (fz) * WZ;
            var m = XYZ_D50_TO_SRGB;
            r = gam (m[0] * x + m[1] * y + m[2] * z);
            g = gam (m[3] * x + m[4] * y + m[5] * z);
            b = gam (m[6] * x + m[7] * y + m[8] * z);
        }

        public static void generic_rgb_to_cmyk (double r, double g, double b, out double c, out double m, out double y, out double k) {
            ColorMath.rgb_to_cmyk (r.clamp (0, 1), g.clamp (0, 1), b.clamp (0, 1), out c, out m, out y, out k);
            double total = c + m + y + k;
            if (total > 3.0) {
                double f = (3.0 - k) / double.max (0.001, c + m + y);
                c *= f;
                m *= f;
                y *= f;
            }
        }

#if HAVE_LCMS
        private static string profile_description (Lcms.Profile p) {
            uint32 n = p.info_ascii (Lcms.INFO_DESCRIPTION, "en", "US", null, 0);
            if (n == 0) return "";
            var buf = new char[n + 1];
            p.info_ascii (Lcms.INFO_DESCRIPTION, "en", "US", buf, n);
            buf[n] = 0;
            return ((string) buf).strip ();
        }

        private static int sample_forward (uint16[] input, uint16[] output, void* cargo) {
            double c = input[0] / 65535.0, m = input[1] / 65535.0, y = input[2] / 65535.0, k = input[3] / 65535.0;
            var rgb = ColorMath.cmyk_to_rgb (c, m, y, k);
            double l, a, b;
            rgb_to_lab (rgb.r, rgb.g, rgb.b, out l, out a, out b);
            output[0] = (uint16) Math.round ((l / 100).clamp (0, 1) * 65535);
            output[1] = (uint16) Math.round (((a + 128) * 257).clamp (0, 65535));
            output[2] = (uint16) Math.round (((b + 128) * 257).clamp (0, 65535));
            return 1;
        }

        private static int sample_reverse (uint16[] input, uint16[] output, void* cargo) {
            double l = input[0] / 65535.0 * 100, a = input[1] / 257.0 - 128, b = input[2] / 257.0 - 128;
            double r, g, bl;
            lab_to_rgb (l, a, b, out r, out g, out bl);
            double c, m, y, k;
            generic_rgb_to_cmyk (r, g, bl, out c, out m, out y, out k);
            output[0] = (uint16) Math.round (c * 65535);
            output[1] = (uint16) Math.round (m * 65535);
            output[2] = (uint16) Math.round (y * 65535);
            output[3] = (uint16) Math.round (k * 65535);
            return 1;
        }

        private static Lcms.Profile generic_profile () {
            var p = Lcms.Profile.placeholder ();
            p.set_version (2.1);
            p.set_device_class (Lcms.SIG_OUTPUT_CLASS);
            p.set_color_space (Lcms.SIG_CMYK_DATA);
            p.set_pcs (Lcms.SIG_LAB_DATA);
            p.set_rendering_intent (1);
            var desc = new Lcms.MLU (null, 1);
            desc.set_ascii ("en", "US", GENERIC_NAME);
            p.write_tag (Lcms.SIG_DESCRIPTION, desc);
            var cprt = new Lcms.MLU (null, 1);
            cprt.set_ascii ("en", "US", "No copyright, use freely");
            p.write_tag (Lcms.SIG_COPYRIGHT, cprt);
            p.write_tag (Lcms.SIG_MEDIA_WHITE_POINT, Lcms.d50_xyz ());
            var fwd = new Lcms.Pipeline (null, 4, 3);
            var fs = Lcms.Stage.clut16 (null, 9, 4, 3);
            fs.sample16 (sample_forward, null, 0);
            fwd.insert_stage (Lcms.AT_END, (owned) fs);
            var rev = new Lcms.Pipeline (null, 3, 4);
            var rs = Lcms.Stage.clut16 (null, 33, 3, 4);
            rs.sample16 (sample_reverse, null, 0);
            rev.insert_stage (Lcms.AT_END, (owned) rs);
            foreach (uint32 sig in new uint32[] { Lcms.SIG_ATOB0, Lcms.SIG_ATOB1, Lcms.SIG_ATOB2 }) p.write_tag (sig, fwd);
            foreach (uint32 sig in new uint32[] { Lcms.SIG_BTOA0, Lcms.SIG_BTOA1, Lcms.SIG_BTOA2 }) p.write_tag (sig, rev);
            return p;
        }
#else
        private static uint8[] generic_profile_bytes () {
            return new uint8[0];
        }
#endif
    }
}
