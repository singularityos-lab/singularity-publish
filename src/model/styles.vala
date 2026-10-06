namespace Singularity.Apps.Publish {

    public enum TextAlign {
        LEFT,
        CENTER,
        RIGHT,
        JUSTIFY,
        JUSTIFY_ALL;

        public string to_string () {
            switch (this) {
                case CENTER: return "center";
                case RIGHT: return "right";
                case JUSTIFY: return "justify";
                case JUSTIFY_ALL: return "justify-all";
                default: return "left";
            }
        }

        public static TextAlign parse (string s) {
            switch (s) {
                case "center": return CENTER;
                case "right": return RIGHT;
                case "justify": return JUSTIFY;
                case "justify-all": return JUSTIFY_ALL;
                default: return LEFT;
            }
        }
    }

    public enum TabKind {
        LEFT,
        CENTER,
        RIGHT,
        DECIMAL;

        public string to_string () {
            switch (this) {
                case CENTER: return "center";
                case RIGHT: return "right";
                case DECIMAL: return "decimal";
                default: return "left";
            }
        }

        public static TabKind parse (string s) {
            switch (s) {
                case "center": return CENTER;
                case "right": return RIGHT;
                case "decimal": return DECIMAL;
                default: return LEFT;
            }
        }
    }

    public class TabStop {
        public double pos;
        public TabKind kind;
        public string leader;

        public TabStop (double pos, TabKind kind = TabKind.LEFT, string leader = "") {
            this.pos = pos;
            this.kind = kind;
            this.leader = leader;
        }

        public static string serialize (Gee.List<TabStop> tabs) {
            var sb = new StringBuilder ();
            foreach (var t in tabs) {
                if (sb.len > 0) sb.append (";");
                sb.append ("%s:%s:%s".printf (XmlOut.num (t.pos), t.kind.to_string (), Uri.escape_string (t.leader, "", true)));
            }
            return sb.str;
        }

        public static Gee.ArrayList<TabStop> parse (string? s) {
            var list = new Gee.ArrayList<TabStop> ();
            if (s == null || s == "") return list;
            foreach (string part in s.split (";")) {
                string[] f = part.split (":");
                if (f.length < 1) continue;
                double p = Units.parse_num (f[0], double.NAN);
                if (p.is_nan ()) continue;
                string leader = f.length > 2 ? (Uri.unescape_string (f[2]) ?? "") : "";
                list.add (new TabStop (p, f.length > 1 ? TabKind.parse (f[1]) : TabKind.LEFT, leader));
            }
            list.sort ((a, b) => a.pos < b.pos ? -1 : (a.pos > b.pos ? 1 : 0));
            return list;
        }
    }

    public class CharFormat {
        public string? font = null;
        public double size = double.NAN;
        public int bold = -1;
        public int italic = -1;
        public int underline = -1;
        public int strike = -1;
        public string? color = null;
        public double tracking = double.NAN;
        public double baseline_shift = double.NAN;
        public int caps = -1;
        public int position = -1;
        public string? features = null;
        public string? variations = null;
        public int kerning = -1;
        public int ligatures = -1;
        public string? lang = null;
        public string? link = null;
        public string? outline_color = null;
        public double outline_width = double.NAN;
        public int text_shadow = -1;
        public string? glow_color = null;
        public double glow_size = double.NAN;
        public int reflection = -1;
        public int emboss = -1;

        public CharFormat () {
        }

        public static CharFormat defaults () {
            var f = new CharFormat ();
            f.font = "Inter";
            f.size = 11;
            f.bold = 0;
            f.italic = 0;
            f.underline = 0;
            f.strike = 0;
            f.color = ColorRef.BLACK;
            f.tracking = 0;
            f.baseline_shift = 0;
            f.caps = 0;
            f.position = 0;
            f.features = "";
            f.variations = "";
            f.kerning = 1;
            f.ligatures = 1;
            f.lang = "en";
            f.link = "";
            f.outline_color = "";
            f.outline_width = 0;
            f.text_shadow = 0;
            f.glow_color = "";
            f.glow_size = 0;
            f.reflection = 0;
            f.emboss = 0;
            return f;
        }

        public bool has_effects () {
            return (outline_color != null && outline_color != "" && !outline_width.is_nan () && outline_width > 0) || text_shadow == 1 || (glow_color != null && glow_color != "" && !glow_size.is_nan () && glow_size > 0) || reflection == 1 || emboss > 0;
        }

        public void apply (CharFormat o) {
            if (o.font != null) font = o.font;
            if (!o.size.is_nan ()) size = o.size;
            if (o.bold >= 0) bold = o.bold;
            if (o.italic >= 0) italic = o.italic;
            if (o.underline >= 0) underline = o.underline;
            if (o.strike >= 0) strike = o.strike;
            if (o.color != null) color = o.color;
            if (!o.tracking.is_nan ()) tracking = o.tracking;
            if (!o.baseline_shift.is_nan ()) baseline_shift = o.baseline_shift;
            if (o.caps >= 0) caps = o.caps;
            if (o.position >= 0) position = o.position;
            if (o.features != null) features = o.features;
            if (o.variations != null) variations = o.variations;
            if (o.kerning >= 0) kerning = o.kerning;
            if (o.ligatures >= 0) ligatures = o.ligatures;
            if (o.lang != null) lang = o.lang;
            if (o.link != null) link = o.link;
            if (o.outline_color != null) outline_color = o.outline_color;
            if (!o.outline_width.is_nan ()) outline_width = o.outline_width;
            if (o.text_shadow >= 0) text_shadow = o.text_shadow;
            if (o.glow_color != null) glow_color = o.glow_color;
            if (!o.glow_size.is_nan ()) glow_size = o.glow_size;
            if (o.reflection >= 0) reflection = o.reflection;
            if (o.emboss >= 0) emboss = o.emboss;
        }

        public CharFormat clone () {
            var f = new CharFormat ();
            f.apply (this);
            return f;
        }

        public bool is_empty () {
            return font == null && size.is_nan () && bold < 0 && italic < 0 && underline < 0 && strike < 0 && color == null && tracking.is_nan () && baseline_shift.is_nan () && caps < 0 && position < 0 && features == null && variations == null && kerning < 0 && ligatures < 0 && lang == null && link == null && outline_color == null && outline_width.is_nan () && text_shadow < 0 && glow_color == null && glow_size.is_nan () && reflection < 0 && emboss < 0;
        }

        private static bool deq (double a, double b) {
            return (a.is_nan () && b.is_nan ()) || Math.fabs (a - b) < 1e-9;
        }

        public bool equals (CharFormat o) {
            return font == o.font && deq (size, o.size) && bold == o.bold && italic == o.italic && underline == o.underline && strike == o.strike && color == o.color && deq (tracking, o.tracking) && deq (baseline_shift, o.baseline_shift) && caps == o.caps && position == o.position && features == o.features && variations == o.variations && kerning == o.kerning && ligatures == o.ligatures && lang == o.lang && link == o.link && outline_color == o.outline_color && deq (outline_width, o.outline_width) && text_shadow == o.text_shadow && glow_color == o.glow_color && deq (glow_size, o.glow_size) && reflection == o.reflection && emboss == o.emboss;
        }

        public void write (XmlOut x) {
            if (font != null) x.a ("font", font);
            if (!size.is_nan ()) x.ad ("size", size);
            if (bold >= 0) x.ai ("bold", bold);
            if (italic >= 0) x.ai ("italic", italic);
            if (underline >= 0) x.ai ("underline", underline);
            if (strike >= 0) x.ai ("strike", strike);
            if (color != null) x.a ("color", color);
            if (!tracking.is_nan ()) x.ad ("tracking", tracking);
            if (!baseline_shift.is_nan ()) x.ad ("shift", baseline_shift);
            if (caps >= 0) x.ai ("caps", caps);
            if (position >= 0) x.ai ("position", position);
            if (features != null) x.a ("features", features);
            if (variations != null) x.a ("variations", variations);
            if (kerning >= 0) x.ai ("kerning", kerning);
            if (ligatures >= 0) x.ai ("ligatures", ligatures);
            if (lang != null) x.a ("lang", lang);
            if (link != null) x.a ("link", link);
            if (outline_color != null) x.a ("outline-color", outline_color);
            if (!outline_width.is_nan ()) x.ad ("outline-width", outline_width);
            if (text_shadow >= 0) x.ai ("text-shadow", text_shadow);
            if (glow_color != null) x.a ("glow-color", glow_color);
            if (!glow_size.is_nan ()) x.ad ("glow-size", glow_size);
            if (reflection >= 0) x.ai ("reflection", reflection);
            if (emboss >= 0) x.ai ("emboss", emboss);
        }

        public static CharFormat read (Xml.Node* n) {
            var f = new CharFormat ();
            f.font = XmlIn.attr (n, "font");
            f.size = XmlIn.double_attr (n, "size", double.NAN);
            f.bold = XmlIn.int_attr (n, "bold", -1);
            f.italic = XmlIn.int_attr (n, "italic", -1);
            f.underline = XmlIn.int_attr (n, "underline", -1);
            f.strike = XmlIn.int_attr (n, "strike", -1);
            f.color = XmlIn.attr (n, "color");
            f.tracking = XmlIn.double_attr (n, "tracking", double.NAN);
            f.baseline_shift = XmlIn.double_attr (n, "shift", double.NAN);
            f.caps = XmlIn.int_attr (n, "caps", -1);
            f.position = XmlIn.int_attr (n, "position", -1);
            f.features = XmlIn.attr (n, "features");
            f.variations = XmlIn.attr (n, "variations");
            f.kerning = XmlIn.int_attr (n, "kerning", -1);
            f.ligatures = XmlIn.int_attr (n, "ligatures", -1);
            f.lang = XmlIn.attr (n, "lang");
            f.link = XmlIn.attr (n, "link");
            f.outline_color = XmlIn.attr (n, "outline-color");
            f.outline_width = XmlIn.double_attr (n, "outline-width", double.NAN);
            f.text_shadow = XmlIn.int_attr (n, "text-shadow", -1);
            f.glow_color = XmlIn.attr (n, "glow-color");
            f.glow_size = XmlIn.double_attr (n, "glow-size", double.NAN);
            f.reflection = XmlIn.int_attr (n, "reflection", -1);
            f.emboss = XmlIn.int_attr (n, "emboss", -1);
            return f;
        }
    }

    public class ParaFormat {
        public int align = -1;
        public double left_indent = double.NAN;
        public double right_indent = double.NAN;
        public double first_indent = double.NAN;
        public double space_before = double.NAN;
        public double space_after = double.NAN;
        public double leading = double.NAN;
        public int drop_lines = -1;
        public int drop_chars = -1;
        public int hyphenate = -1;
        public int align_grid = -1;
        public int list_type = -1;
        public string? bullet = null;
        public int number_format = -1;
        public int number_start = -1;
        public int list_level = -1;
        public string? tabs = null;
        public int keep_next = -1;
        public int optical = -1;
        public int direction = -1;
        public int keep_lines = -1;
        public string? rule_above = null;
        public string? rule_below = null;
        public int composer = -1;
        public double word_min = double.NAN;
        public double word_opt = double.NAN;
        public double word_max = double.NAN;
        public double letter_min = double.NAN;
        public double letter_opt = double.NAN;
        public double letter_max = double.NAN;
        public double glyph_min = double.NAN;
        public double glyph_opt = double.NAN;
        public double glyph_max = double.NAN;
        public int hyph_min_word = -1;
        public int hyph_before = -1;
        public int hyph_after = -1;
        public int hyph_limit = -1;
        public double hyph_zone = double.NAN;
        public int hyph_caps = -1;

        public ParaFormat () {
        }

        public static ParaFormat defaults () {
            var f = new ParaFormat ();
            f.align = 0;
            f.left_indent = 0;
            f.right_indent = 0;
            f.first_indent = 0;
            f.space_before = 0;
            f.space_after = 0;
            f.leading = 0;
            f.drop_lines = 0;
            f.drop_chars = 1;
            f.hyphenate = 1;
            f.align_grid = 0;
            f.list_type = 0;
            f.bullet = "•";
            f.number_format = 0;
            f.number_start = 1;
            f.list_level = 0;
            f.tabs = "";
            f.keep_next = 0;
            f.optical = 0;
            f.direction = 0;
            f.keep_lines = 0;
            f.rule_above = "";
            f.rule_below = "";
            f.composer = 0;
            f.word_min = 80;
            f.word_opt = 100;
            f.word_max = 133;
            f.letter_min = 0;
            f.letter_opt = 0;
            f.letter_max = 0;
            f.glyph_min = 100;
            f.glyph_opt = 100;
            f.glyph_max = 100;
            f.hyph_min_word = 5;
            f.hyph_before = 2;
            f.hyph_after = 2;
            f.hyph_limit = 3;
            f.hyph_zone = 36;
            f.hyph_caps = 1;
            return f;
        }

        public TextAlign text_align () {
            return (TextAlign) align.clamp (0, 4);
        }

        public void apply (ParaFormat o) {
            if (o.align >= 0) align = o.align;
            if (!o.left_indent.is_nan ()) left_indent = o.left_indent;
            if (!o.right_indent.is_nan ()) right_indent = o.right_indent;
            if (!o.first_indent.is_nan ()) first_indent = o.first_indent;
            if (!o.space_before.is_nan ()) space_before = o.space_before;
            if (!o.space_after.is_nan ()) space_after = o.space_after;
            if (!o.leading.is_nan ()) leading = o.leading;
            if (o.drop_lines >= 0) drop_lines = o.drop_lines;
            if (o.drop_chars >= 0) drop_chars = o.drop_chars;
            if (o.hyphenate >= 0) hyphenate = o.hyphenate;
            if (o.align_grid >= 0) align_grid = o.align_grid;
            if (o.list_type >= 0) list_type = o.list_type;
            if (o.bullet != null) bullet = o.bullet;
            if (o.number_format >= 0) number_format = o.number_format;
            if (o.number_start >= 0) number_start = o.number_start;
            if (o.list_level >= 0) list_level = o.list_level;
            if (o.tabs != null) tabs = o.tabs;
            if (o.keep_next >= 0) keep_next = o.keep_next;
            if (o.optical >= 0) optical = o.optical;
            if (o.direction >= 0) direction = o.direction;
            if (o.keep_lines >= 0) keep_lines = o.keep_lines;
            if (o.rule_above != null) rule_above = o.rule_above;
            if (o.rule_below != null) rule_below = o.rule_below;
            if (o.composer >= 0) composer = o.composer;
            if (!o.word_min.is_nan ()) word_min = o.word_min;
            if (!o.word_opt.is_nan ()) word_opt = o.word_opt;
            if (!o.word_max.is_nan ()) word_max = o.word_max;
            if (!o.letter_min.is_nan ()) letter_min = o.letter_min;
            if (!o.letter_opt.is_nan ()) letter_opt = o.letter_opt;
            if (!o.letter_max.is_nan ()) letter_max = o.letter_max;
            if (!o.glyph_min.is_nan ()) glyph_min = o.glyph_min;
            if (!o.glyph_opt.is_nan ()) glyph_opt = o.glyph_opt;
            if (!o.glyph_max.is_nan ()) glyph_max = o.glyph_max;
            if (o.hyph_min_word >= 0) hyph_min_word = o.hyph_min_word;
            if (o.hyph_before >= 0) hyph_before = o.hyph_before;
            if (o.hyph_after >= 0) hyph_after = o.hyph_after;
            if (o.hyph_limit >= 0) hyph_limit = o.hyph_limit;
            if (!o.hyph_zone.is_nan ()) hyph_zone = o.hyph_zone;
            if (o.hyph_caps >= 0) hyph_caps = o.hyph_caps;
        }

        public void copy_composition (ParaFormat o) {
            composer = o.composer;
            word_min = o.word_min;
            word_opt = o.word_opt;
            word_max = o.word_max;
            letter_min = o.letter_min;
            letter_opt = o.letter_opt;
            letter_max = o.letter_max;
            glyph_min = o.glyph_min;
            glyph_opt = o.glyph_opt;
            glyph_max = o.glyph_max;
            hyph_min_word = o.hyph_min_word;
            hyph_before = o.hyph_before;
            hyph_after = o.hyph_after;
            hyph_limit = o.hyph_limit;
            hyph_zone = o.hyph_zone;
            hyph_caps = o.hyph_caps;
        }

        public ParaFormat clone () {
            var f = new ParaFormat ();
            f.apply (this);
            return f;
        }

        public bool is_empty () {
            return align < 0 && left_indent.is_nan () && right_indent.is_nan () && first_indent.is_nan () && space_before.is_nan () && space_after.is_nan () && leading.is_nan () && drop_lines < 0 && drop_chars < 0 && hyphenate < 0 && align_grid < 0 && list_type < 0 && bullet == null && number_format < 0 && number_start < 0 && list_level < 0 && tabs == null && keep_next < 0 && keep_lines < 0 && rule_above == null && rule_below == null
                && composer < 0 && word_min.is_nan () && word_opt.is_nan () && word_max.is_nan () && letter_min.is_nan () && letter_opt.is_nan () && letter_max.is_nan ()
                && glyph_min.is_nan () && glyph_opt.is_nan () && glyph_max.is_nan () && hyph_min_word < 0 && hyph_before < 0 && hyph_after < 0 && hyph_limit < 0 && hyph_zone.is_nan () && hyph_caps < 0 && optical < 0 && direction < 0;
        }

        public void write (XmlOut x) {
            if (align >= 0) x.a ("align", text_align ().to_string ());
            if (!left_indent.is_nan ()) x.ad ("left-indent", left_indent);
            if (!right_indent.is_nan ()) x.ad ("right-indent", right_indent);
            if (!first_indent.is_nan ()) x.ad ("first-indent", first_indent);
            if (!space_before.is_nan ()) x.ad ("space-before", space_before);
            if (!space_after.is_nan ()) x.ad ("space-after", space_after);
            if (!leading.is_nan ()) x.ad ("leading", leading);
            if (drop_lines >= 0) x.ai ("drop-lines", drop_lines);
            if (drop_chars >= 0) x.ai ("drop-chars", drop_chars);
            if (hyphenate >= 0) x.ai ("hyphenate", hyphenate);
            if (align_grid >= 0) x.ai ("align-grid", align_grid);
            if (list_type >= 0) x.ai ("list", list_type);
            if (bullet != null) x.a ("bullet", bullet);
            if (number_format >= 0) x.ai ("number-format", number_format);
            if (number_start >= 0) x.ai ("number-start", number_start);
            if (list_level >= 0) x.ai ("list-level", list_level);
            if (tabs != null) x.a ("tabs", tabs);
            if (keep_next >= 0) x.ai ("keep-next", keep_next);
            if (optical >= 0) x.ai ("optical", optical);
            if (direction >= 0) x.ai ("direction", direction);
            if (keep_lines >= 0) x.ai ("keep-lines", keep_lines);
            if (rule_above != null) x.a ("rule-above", rule_above);
            if (rule_below != null) x.a ("rule-below", rule_below);
            if (composer >= 0) x.ai ("composer", composer);
            if (!word_min.is_nan ()) x.ad ("word-min", word_min);
            if (!word_opt.is_nan ()) x.ad ("word-opt", word_opt);
            if (!word_max.is_nan ()) x.ad ("word-max", word_max);
            if (!letter_min.is_nan ()) x.ad ("letter-min", letter_min);
            if (!letter_opt.is_nan ()) x.ad ("letter-opt", letter_opt);
            if (!letter_max.is_nan ()) x.ad ("letter-max", letter_max);
            if (!glyph_min.is_nan ()) x.ad ("glyph-min", glyph_min);
            if (!glyph_opt.is_nan ()) x.ad ("glyph-opt", glyph_opt);
            if (!glyph_max.is_nan ()) x.ad ("glyph-max", glyph_max);
            if (hyph_min_word >= 0) x.ai ("hyph-min-word", hyph_min_word);
            if (hyph_before >= 0) x.ai ("hyph-before", hyph_before);
            if (hyph_after >= 0) x.ai ("hyph-after", hyph_after);
            if (hyph_limit >= 0) x.ai ("hyph-limit", hyph_limit);
            if (!hyph_zone.is_nan ()) x.ad ("hyph-zone", hyph_zone);
            if (hyph_caps >= 0) x.ai ("hyph-caps", hyph_caps);
        }

        public static ParaFormat read (Xml.Node* n) {
            var f = new ParaFormat ();
            string? al = XmlIn.attr (n, "align");
            if (al != null) f.align = (int) TextAlign.parse (al);
            f.left_indent = XmlIn.double_attr (n, "left-indent", double.NAN);
            f.right_indent = XmlIn.double_attr (n, "right-indent", double.NAN);
            f.first_indent = XmlIn.double_attr (n, "first-indent", double.NAN);
            f.space_before = XmlIn.double_attr (n, "space-before", double.NAN);
            f.space_after = XmlIn.double_attr (n, "space-after", double.NAN);
            f.leading = XmlIn.double_attr (n, "leading", double.NAN);
            f.drop_lines = XmlIn.int_attr (n, "drop-lines", -1);
            f.drop_chars = XmlIn.int_attr (n, "drop-chars", -1);
            f.hyphenate = XmlIn.int_attr (n, "hyphenate", -1);
            f.align_grid = XmlIn.int_attr (n, "align-grid", -1);
            f.list_type = XmlIn.int_attr (n, "list", -1);
            f.bullet = XmlIn.attr (n, "bullet");
            f.number_format = XmlIn.int_attr (n, "number-format", -1);
            f.number_start = XmlIn.int_attr (n, "number-start", -1);
            f.list_level = XmlIn.int_attr (n, "list-level", -1);
            f.tabs = XmlIn.attr (n, "tabs");
            f.keep_next = XmlIn.int_attr (n, "keep-next", -1);
            f.optical = XmlIn.int_attr (n, "optical", -1);
            f.direction = XmlIn.int_attr (n, "direction", -1);
            f.keep_lines = XmlIn.int_attr (n, "keep-lines", -1);
            f.rule_above = XmlIn.attr (n, "rule-above");
            f.rule_below = XmlIn.attr (n, "rule-below");
            f.composer = XmlIn.int_attr (n, "composer", -1);
            f.word_min = XmlIn.double_attr (n, "word-min", double.NAN);
            f.word_opt = XmlIn.double_attr (n, "word-opt", double.NAN);
            f.word_max = XmlIn.double_attr (n, "word-max", double.NAN);
            f.letter_min = XmlIn.double_attr (n, "letter-min", double.NAN);
            f.letter_opt = XmlIn.double_attr (n, "letter-opt", double.NAN);
            f.letter_max = XmlIn.double_attr (n, "letter-max", double.NAN);
            f.glyph_min = XmlIn.double_attr (n, "glyph-min", double.NAN);
            f.glyph_opt = XmlIn.double_attr (n, "glyph-opt", double.NAN);
            f.glyph_max = XmlIn.double_attr (n, "glyph-max", double.NAN);
            f.hyph_min_word = XmlIn.int_attr (n, "hyph-min-word", -1);
            f.hyph_before = XmlIn.int_attr (n, "hyph-before", -1);
            f.hyph_after = XmlIn.int_attr (n, "hyph-after", -1);
            f.hyph_limit = XmlIn.int_attr (n, "hyph-limit", -1);
            f.hyph_zone = XmlIn.double_attr (n, "hyph-zone", double.NAN);
            f.hyph_caps = XmlIn.int_attr (n, "hyph-caps", -1);
            return f;
        }
    }

    public class ParagraphStyle {
        public string name;
        public string group = "";
        public string based_on = "";
        public string next = "";
        public ParaFormat para = new ParaFormat ();
        public CharFormat chars = new CharFormat ();
        public Gee.ArrayList<NestedStyle> nested = new Gee.ArrayList<NestedStyle> ();
        public Gee.ArrayList<GrepStyle> grep = new Gee.ArrayList<GrepStyle> ();
        public string tag = "";

        public ParagraphStyle (string name, string based_on = "") {
            this.name = name;
            this.based_on = based_on;
        }

        public ParagraphStyle clone () {
            var s = new ParagraphStyle (name, based_on);
            s.next = next;
            s.group = group;
            s.para = para.clone ();
            s.chars = chars.clone ();
            foreach (var n in nested) s.nested.add (n.clone ());
            foreach (var g in grep) s.grep.add (g.clone ());
            s.tag = tag;
            return s;
        }
    }

    public class CharacterStyle {
        public string name;
        public string group = "";
        public string based_on = "";
        public CharFormat chars = new CharFormat ();

        public CharacterStyle (string name, string based_on = "") {
            this.name = name;
            this.based_on = based_on;
        }

        public CharacterStyle clone () {
            var s = new CharacterStyle (name, based_on);
            s.chars = chars.clone ();
            s.group = group;
            return s;
        }
    }

    public class StyleSheet {
        public const string BASIC = "Basic Paragraph";
        public const string HYPERLINK = "Hyperlink";
        public Gee.ArrayList<ParagraphStyle> paragraph = new Gee.ArrayList<ParagraphStyle> ();
        public Gee.ArrayList<CharacterStyle> character = new Gee.ArrayList<CharacterStyle> ();

        public StyleSheet () {
        }

        public static StyleSheet standard () {
            var s = new StyleSheet ();
            var basic = new ParagraphStyle (BASIC);
            basic.chars.font = "Inter";
            basic.chars.size = 10.5;
            basic.para.leading = 14;
            basic.para.space_after = 4;
            s.paragraph.add (basic);
            var body = new ParagraphStyle ("Body Text", BASIC);
            body.para.align = (int) TextAlign.JUSTIFY;
            body.para.first_indent = 0;
            s.paragraph.add (body);
            var h1 = new ParagraphStyle ("Heading 1", BASIC);
            h1.chars.size = 26;
            h1.chars.bold = 1;
            h1.para.leading = 30;
            h1.para.space_after = 8;
            h1.para.keep_next = 1;
            h1.para.hyphenate = 0;
            h1.next = "Body Text";
            s.paragraph.add (h1);
            var h2 = new ParagraphStyle ("Heading 2", "Heading 1");
            h2.chars.size = 16;
            h2.para.leading = 20;
            h2.para.space_before = 8;
            h2.para.space_after = 4;
            s.paragraph.add (h2);
            var cap = new ParagraphStyle ("Caption", BASIC);
            cap.chars.size = 8.5;
            cap.chars.italic = 1;
            cap.para.leading = 11;
            s.paragraph.add (cap);
            var bl = new ParagraphStyle ("Bulleted List", BASIC);
            bl.para.list_type = 1;
            bl.para.left_indent = 14;
            bl.para.first_indent = -10;
            s.paragraph.add (bl);
            var nl = new ParagraphStyle ("Numbered List", BASIC);
            nl.para.list_type = 2;
            nl.para.left_indent = 16;
            nl.para.first_indent = -12;
            s.paragraph.add (nl);
            var em = new CharacterStyle ("Emphasis");
            em.chars.italic = 1;
            s.character.add (em);
            var strong = new CharacterStyle ("Strong");
            strong.chars.bold = 1;
            s.character.add (strong);
            var link = new CharacterStyle (HYPERLINK);
            link.chars.underline = 1;
            link.chars.color = ColorRef.swatch (HYPERLINK);
            s.character.add (link);
            return s;
        }

        public ParagraphStyle? find_paragraph (string name) {
            foreach (var p in paragraph) if (p.name == name) return p;
            return null;
        }

        public CharacterStyle? find_character (string name) {
            foreach (var c in character) if (c.name == name) return c;
            return null;
        }

        public Gee.ArrayList<ParagraphStyle> para_chain (string name) {
            var chain = new Gee.ArrayList<ParagraphStyle> ();
            string cur = name;
            int guard = 0;
            while (cur != "" && guard++ < 32) {
                var s = find_paragraph (cur);
                if (s == null || chain.contains (s)) break;
                chain.insert (0, s);
                cur = s.based_on;
            }
            return chain;
        }

        public void resolve_paragraph (string name, ParaFormat para_out, CharFormat chars_out) {
            foreach (var s in para_chain (name)) {
                para_out.apply (s.para);
                chars_out.apply (s.chars);
            }
        }

        public void resolve_character (string name, CharFormat out_fmt) {
            var chain = new Gee.ArrayList<CharacterStyle> ();
            string cur = name;
            int guard = 0;
            while (cur != "" && guard++ < 32) {
                var s = find_character (cur);
                if (s == null || chain.contains (s)) break;
                chain.insert (0, s);
                cur = s.based_on;
            }
            foreach (var s in chain) out_fmt.apply (s.chars);
        }

        public bool would_cycle (string style, string based_on) {
            string cur = based_on;
            int guard = 0;
            while (cur != "" && guard++ < 64) {
                if (cur == style) return true;
                var s = find_paragraph (cur);
                if (s == null) return false;
                cur = s.based_on;
            }
            return false;
        }

        public string unique_paragraph_name (string base_name) {
            if (find_paragraph (base_name) == null) return base_name;
            for (int i = 2; ; i++) {
                string n = "%s %d".printf (base_name, i);
                if (find_paragraph (n) == null) return n;
            }
        }

        public string unique_character_name (string base_name) {
            if (find_character (base_name) == null) return base_name;
            for (int i = 2; ; i++) {
                string n = "%s %d".printf (base_name, i);
                if (find_character (n) == null) return n;
            }
        }

        public StyleSheet clone () {
            var s = new StyleSheet ();
            foreach (var p in paragraph) s.paragraph.add (p.clone ());
            foreach (var c in character) s.character.add (c.clone ());
            return s;
        }
    }
}
