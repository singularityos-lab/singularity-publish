namespace Singularity.Apps.Publish {

    public class ColorScheme {
        public const string MAIN = "Main";
        public const string[] SLOTS = { "Main", "Accent 1", "Accent 2", "Accent 3", "Accent 4", "Accent 5", "Hyperlink", "Followed Hyperlink" };
        public string name;
        public string[] colors;
        public bool custom = false;

        public ColorScheme (string name, string[] colors) {
            this.name = name;
            this.colors = colors;
        }

        public static string slot_label (int i) {
            switch (i) {
                case 0: return _("Main");
                case 1: return _("Accent 1");
                case 2: return _("Accent 2");
                case 3: return _("Accent 3");
                case 4: return _("Accent 4");
                case 5: return _("Accent 5");
                case 6: return _("Hyperlink");
                default: return _("Followed Hyperlink");
            }
        }

        public static string slot_spec (int i, double tint = 100) {
            return ColorRef.swatch (SLOTS[i], tint);
        }

        private static Gee.ArrayList<ColorScheme>? builtin = null;

        private static void b (string name, string a, string c1, string c2, string c3, string c4, string c5, string link = "#0b62c4", string followed = "#7a3fb0") {
            builtin.add (new ColorScheme (name, { a, c1, c2, c3, c4, c5, link, followed }));
        }

        public static Gee.ArrayList<ColorScheme> builtins () {
            if (builtin != null) return builtin;
            builtin = new Gee.ArrayList<ColorScheme> ();
            b ("Alpine", "#1f2a44", "#3c7fb1", "#9fc5e8", "#6b8e23", "#e8eef4", "#c9a227");
            b ("Aqua", "#0b3d4c", "#1aa6b7", "#7fd6de", "#f2b134", "#e6f6f8", "#ed6a5a");
            b ("Berry", "#3b0f2e", "#8e2461", "#d86a9e", "#5e3c99", "#f6e6ef", "#f4a259");
            b ("Bluebird", "#102a4c", "#2f6fb5", "#88b7e8", "#f2c14e", "#eaf2fb", "#a33b3b");
            b ("Brown", "#3e2723", "#795548", "#bcaaa4", "#8d6e63", "#efebe9", "#c77d3a");
            b ("Burgundy", "#2b0b12", "#7b1e2b", "#c05668", "#d9a066", "#f5e9eb", "#4a5d23");
            b ("Citrus", "#2f3b10", "#8cb82b", "#f5c518", "#f28c28", "#fbf8e6", "#2d7dd2");
            b ("Clay", "#3a2418", "#b5562a", "#e3a878", "#6d8a96", "#f7ece3", "#4b6b3e");
            b ("Cranberry", "#2d0a13", "#9b1d33", "#e0788a", "#2f5d62", "#f8e8eb", "#e1b04a");
            b ("Crocus", "#2a1e3f", "#6a4c9c", "#b8a3dc", "#f0b429", "#f3effa", "#4f9d69");
            b ("Dark Blue", "#0a1a33", "#1d3f72", "#5b7fb5", "#b4c7e7", "#e9eef6", "#d99a2b");
            b ("Desert", "#3b2a1a", "#c1693c", "#e9c46a", "#8a9a5b", "#f8f1e5", "#2a9d8f");
            b ("Field", "#23331a", "#5a8f29", "#b5d99c", "#e0a526", "#f1f7ea", "#7a4f2a");
            b ("Fjord", "#10283a", "#2c6e8f", "#7fb3cf", "#d5e3ea", "#eef4f7", "#b85c38");
            b ("Garnet", "#2a0808", "#8f1d1d", "#d46a6a", "#b08d57", "#f7eaea", "#39424e");
            b ("Glacier", "#15324a", "#4e8fbf", "#a9d1ee", "#dbe9f4", "#f2f8fc", "#6c5b7b");
            b ("Green", "#0f2f1c", "#2e7d32", "#81c784", "#c5e1a5", "#eef6ec", "#f9a825");
            b ("Grove", "#1f2d16", "#4b7a2b", "#9cc36f", "#a0522d", "#f0f5e8", "#e3b23c");
            b ("Harbor", "#132536", "#335c81", "#65a3c9", "#e07a5f", "#edf3f8", "#f2cc8f");
            b ("Heather", "#2c2433", "#7d5e8c", "#c7aed6", "#8fa98b", "#f4eff7", "#d1848b");
            b ("Island", "#083d3a", "#12a58a", "#79d7c2", "#ffb347", "#e8f8f4", "#ff6f59");
            b ("Ivy", "#122b1d", "#2f6b42", "#7fb28f", "#d4b483", "#edf5ef", "#8c3b3b");
            b ("Lagoon", "#0d2f3f", "#1b7f9e", "#6cc3d5", "#f4d35e", "#e7f4f8", "#ee964b");
            b ("Lilac", "#2f2340", "#8e6bbf", "#d0bdf0", "#f2a7c3", "#f6f1fc", "#5a8f7b");
            b ("Mahogany", "#2a1410", "#7a3325", "#c98b6b", "#d9b26f", "#f6ece6", "#34495e");
            b ("Marine", "#08223a", "#0f5c8c", "#4aa3d8", "#9fd3f0", "#e9f4fb", "#f28f3b");
            b ("Meadow", "#1d3313", "#5b9a31", "#b7dd8a", "#f2d479", "#f2f8ea", "#9b5de5");
            b ("Mist", "#2a3440", "#6c7a89", "#aeb9c4", "#d7dee5", "#f3f5f7", "#8a6f4d");
            b ("Monarch", "#1f140c", "#d9731a", "#f2b56b", "#3a3a3a", "#fbf1e6", "#6a994e");
            b ("Moss", "#232b16", "#667a33", "#b3c27a", "#8b6f47", "#f2f4e8", "#c05746");
            b ("Mulberry", "#2b0f2a", "#7a2a74", "#c774bf", "#e3b35b", "#f7ebf6", "#3d7068");
            b ("Navy", "#0a1630", "#1b2f5e", "#3f5f9e", "#c9a227", "#e8ecf4", "#a23b2a");
            b ("Nutmeg", "#2d1b0e", "#8a5a2b", "#d2a679", "#6e7f4f", "#f6efe6", "#b23a48");
            b ("Ocean", "#06283d", "#1363df", "#47b5ff", "#dff6ff", "#eef8ff", "#f5a623");
            b ("Olive", "#262a10", "#6b7a1f", "#b6c26b", "#d9a441", "#f3f4e6", "#7b3f61");
            b ("Orange", "#2e1405", "#e8590c", "#ffa94d", "#1c7ed6", "#fff4e6", "#5c940d");
            b ("Orchid", "#2e1233", "#a04ca8", "#e0a3e6", "#5fa8a0", "#f8edf9", "#e8b64c");
            b ("Parrot", "#10261a", "#1f9d55", "#e03131", "#fab005", "#eef8f1", "#1971c2");
            b ("Pebbles", "#2b2b2b", "#707070", "#b0a898", "#d9d2c5", "#f4f2ee", "#5c7c8a");
            b ("Prairie", "#302612", "#a67c2e", "#e3c67b", "#6d8a3b", "#f8f3e4", "#8d3b72");
            b ("Rain Forest", "#0c2410", "#1b5e20", "#66bb6a", "#8d6e63", "#ebf5ec", "#ffb300");
            b ("Red", "#2b0404", "#c62828", "#ef9a9a", "#37474f", "#fdecea", "#f9a825");
            b ("Redwood", "#2a120c", "#8c3b24", "#d08a6b", "#4f6d3a", "#f6ebe5", "#d9a03f");
            b ("Reef", "#0a2c33", "#00897b", "#ff7043", "#ffca28", "#e6f5f3", "#5e35b1");
            b ("Sagebrush", "#27301f", "#7d8f69", "#c2cfb2", "#b38b59", "#f2f5ee", "#6b4f7a");
            b ("Sapphire", "#0b1640", "#1e3fae", "#6b8ef0", "#c0cdf7", "#edf1fd", "#d4a017");
            b ("Shamrock", "#0f2a14", "#2e8b3a", "#95d5a0", "#f2e394", "#edf8ef", "#b8336a");
            b ("Sienna", "#2f150b", "#a0522d", "#e2a27a", "#4f6d7a", "#f8ede6", "#c9a227");
            b ("Spice", "#2e0f0a", "#b3361f", "#f09e5b", "#6a4a3c", "#fbeee6", "#35776d");
            b ("Summer", "#1f3b4d", "#ff6b6b", "#ffd166", "#06d6a0", "#fff8ec", "#118ab2");
            b ("Sunrise", "#3a1f0a", "#f08a24", "#ffcf56", "#e84a5f", "#fff6e8", "#2a9d8f");
            b ("Sunset", "#2a0f1f", "#d1495b", "#edae49", "#00798c", "#fcefe9", "#30638e");
            b ("Teal", "#062b2b", "#0f766e", "#5eead4", "#fbbf24", "#e7f7f5", "#be123c");
            b ("Tidepool", "#0e2a36", "#2a7f8f", "#8cc7c9", "#e9a46a", "#ecf6f7", "#6d597a");
            b ("Trek", "#232323", "#4f6d4b", "#a4b494", "#c47b3c", "#f1f1ec", "#2f5d8a");
            b ("Tropics", "#0b2d25", "#00a896", "#f15bb5", "#fee440", "#e9fbf8", "#9b5de5");
            b ("Tuscany", "#2e1b12", "#b5652b", "#e8b86d", "#6b7f3a", "#f9f0e3", "#7a2e3a");
            b ("Vineyard", "#241026", "#5f2a62", "#a86aa4", "#7a9a3a", "#f3ecf4", "#d9a441");
            b ("Waterfall", "#10283b", "#3a7ca5", "#81c3d7", "#d9dcd6", "#eef5f8", "#2f6690");
            b ("Wildflower", "#2e1f33", "#c9557e", "#f4a261", "#6a4c93", "#fbeff3", "#2a9d8f");
            return builtin;
        }

        public static string custom_path () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "publish", "color-schemes.ini");
        }

        public static Gee.ArrayList<ColorScheme> customs () {
            var l = new Gee.ArrayList<ColorScheme> ();
            var kf = new KeyFile ();
            try {
                kf.load_from_file (custom_path (), KeyFileFlags.NONE);
                foreach (string g in kf.get_groups ()) {
                    string[] cols = new string[SLOTS.length];
                    for (int i = 0; i < SLOTS.length; i++) cols[i] = kf.has_key (g, "c%d".printf (i)) ? kf.get_string (g, "c%d".printf (i)) : "#000000";
                    var cs = new ColorScheme (g, cols);
                    cs.custom = true;
                    l.add (cs);
                }
            } catch (Error e) {
            }
            return l;
        }

        public static void save_custom (ColorScheme cs) throws Error {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (custom_path (), KeyFileFlags.NONE);
            } catch (Error e) {
            }
            for (int i = 0; i < SLOTS.length; i++) kf.set_string (cs.name, "c%d".printf (i), cs.colors[i]);
            DirUtils.create_with_parents (Path.get_dirname (custom_path ()), 0700);
            kf.save_to_file (custom_path ());
        }

        public static void delete_custom (string name) throws Error {
            var kf = new KeyFile ();
            kf.load_from_file (custom_path (), KeyFileFlags.NONE);
            if (kf.has_group (name)) kf.remove_group (name);
            kf.save_to_file (custom_path ());
        }

        public static Gee.ArrayList<ColorScheme> all () {
            var l = new Gee.ArrayList<ColorScheme> ();
            l.add_all (customs ());
            l.add_all (builtins ());
            return l;
        }

        public static ColorScheme? find (string name) {
            foreach (var cs in all ()) if (cs.name == name) return cs;
            return null;
        }

        public static ColorScheme from_publication (Publication pub, string name) {
            string[] cols = new string[SLOTS.length];
            for (int i = 0; i < SLOTS.length; i++) {
                var sw = pub.swatch (SLOTS[i]);
                cols[i] = sw != null ? sw.rgba ().to_hex () : "#000000";
            }
            return new ColorScheme (name, cols);
        }

        public void apply (Publication pub) {
            var cm = ColorManager.for_settings (pub.settings);
            for (int i = 0; i < SLOTS.length && i < colors.length; i++) {
                Rgba v;
                if (!Rgba.parse_hex (colors[i], out v)) continue;
                var sw = pub.swatch (SLOTS[i]);
                if (sw == null) {
                    sw = new Swatch.rgb (SLOTS[i], v.r, v.g, v.b);
                    pub.swatches.add (sw);
                }
                sw.spot = false;
                sw.r = v.r;
                sw.g = v.g;
                sw.b = v.b;
                cm.rgb_to_cmyk (v.r, v.g, v.b, out sw.c, out sw.m, out sw.y, out sw.k);
                sw.model = pub.settings.cmyk ? ColorModel.CMYK : ColorModel.RGB;
            }
            pub.color_scheme = name;
        }
    }

    public class FontScheme {
        public string name;
        public string[] heading;
        public string[] body;

        public FontScheme (string name, string[] heading, string[] body) {
            this.name = name;
            this.heading = heading;
            this.body = body;
        }

        private static Gee.ArrayList<FontScheme>? builtin = null;
        private static Gee.HashSet<string>? installed = null;

        private static void b (string name, string[] heading, string[] body) {
            builtin.add (new FontScheme (name, heading, body));
        }

        public static Gee.ArrayList<FontScheme> all () {
            if (builtin != null) return builtin;
            builtin = new Gee.ArrayList<FontScheme> ();
            string[] serif = { "Noto Serif", "DejaVu Serif", "Liberation Serif", "Source Serif 4", "Georgia", "Times New Roman" };
            string[] sans = { "Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Liberation Sans", "Arial" };
            string[] display = { "Noto Serif Display", "Playfair Display", "DejaVu Serif Condensed", "Noto Serif", "Liberation Serif" };
            string[] mono = { "JetBrains Mono", "Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono" };
            string[] rounded = { "Nunito", "Comfortaa", "Quicksand", "Cantarell", "Noto Sans" };
            string[] condensed = { "Noto Sans Display", "Roboto Condensed", "DejaVu Sans Condensed", "Liberation Sans Narrow", "Noto Sans" };
            string[] slab = { "Roboto Slab", "Noto Serif", "DejaVu Serif", "Liberation Serif" };
            string[] script = { "Dancing Script", "Pacifico", "URW Chancery L", "Noto Serif" };
            b ("Office Classic", serif, sans);
            b ("Modern", sans, sans);
            b ("Archival", serif, serif);
            b ("Civic", sans, serif);
            b ("Aspect", display, sans);
            b ("Concourse", condensed, sans);
            b ("Deco", display, serif);
            b ("Economy", condensed, serif);
            b ("Equity", slab, sans);
            b ("Etched", serif, condensed);
            b ("Flow", rounded, rounded);
            b ("Foundry", slab, slab);
            b ("Median", sans, condensed);
            b ("Metro", condensed, condensed);
            b ("Module", mono, sans);
            b ("Opulent", display, display);
            b ("Oriel", display, condensed);
            b ("Origin", rounded, serif);
            b ("Paper", serif, rounded);
            b ("Solstice", sans, display);
            b ("Technic", mono, mono);
            b ("Verve", script, sans);
            b ("Invitation", script, serif);
            b ("Newsprint", slab, serif);
            return builtin;
        }

        public static FontScheme? find (string name) {
            foreach (var f in all ()) if (f.name == name) return f;
            return null;
        }

        public static bool has_font (string family) {
            if (installed == null) {
                installed = new Gee.HashSet<string> ();
                var fm = Pango.CairoFontMap.get_default ();
                Pango.FontFamily[] fams;
                fm.list_families (out fams);
                foreach (var f in fams) installed.add (f.get_name ().down ());
            }
            return installed.contains (family.down ());
        }

        public static string pick (string[] candidates) {
            foreach (string c in candidates) if (has_font (c)) return c;
            return candidates.length > 0 ? candidates[candidates.length - 1] : "Inter";
        }

        public string heading_font () {
            return pick (heading);
        }

        public string body_font () {
            return pick (body);
        }

        public static bool is_heading_style (string name) {
            string n = name.down ();
            return n.contains ("heading") || n.contains ("title") || n.contains ("headline") || n.contains ("masthead");
        }

        public void apply (Publication pub) {
            string h = heading_font (), bf = body_font ();
            foreach (var st in pub.styles.paragraph) {
                if (st.name == StyleSheet.BASIC) st.chars.font = bf;
                else if (is_heading_style (st.name)) st.chars.font = h;
                else if (st.chars.font != null && st.based_on == "") st.chars.font = bf;
            }
            pub.font_scheme = name;
        }
    }
}
