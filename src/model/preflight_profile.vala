namespace Singularity.Apps.Publish {

    public class PreflightProfile {
        public const string BASIC = "Basic";
        public const string PRINT = "Commercial Print";
        public const string DIGITAL = "Digital Publishing";
        public const string NEWSPAPER = "Newspaper";
        public const string ACCESSIBLE = "Accessible PDF";

        public string name;
        public string description = "";
        public bool builtin = false;
        public bool links = true;
        public bool images = true;
        public double min_ppi = 250;
        public double error_ppi = 150;
        public double max_ppi = 0;
        public bool text = true;
        public bool fonts = true;
        public double min_text = 0;
        public bool color = true;
        public bool allow_rgb = false;
        public bool allow_spot = true;
        public double ink_limit = 0;
        public bool transparency = true;
        public bool bleed = true;
        public double min_bleed = 0;
        public bool pasteboard = true;
        public bool empty = true;
        public bool accessibility = false;

        public PreflightProfile (string name) {
            this.name = name;
        }

        public PreflightProfile clone () {
            var p = new PreflightProfile (name);
            p.description = description;
            p.builtin = builtin;
            p.links = links;
            p.images = images;
            p.min_ppi = min_ppi;
            p.error_ppi = error_ppi;
            p.max_ppi = max_ppi;
            p.text = text;
            p.fonts = fonts;
            p.min_text = min_text;
            p.color = color;
            p.allow_rgb = allow_rgb;
            p.allow_spot = allow_spot;
            p.ink_limit = ink_limit;
            p.transparency = transparency;
            p.bleed = bleed;
            p.min_bleed = min_bleed;
            p.pasteboard = pasteboard;
            p.empty = empty;
            p.accessibility = accessibility;
            return p;
        }

        public static Gee.ArrayList<PreflightProfile> builtins () {
            var list = new Gee.ArrayList<PreflightProfile> ();
            var basic = new PreflightProfile (BASIC);
            basic.description = _("Missing links, overset text and missing fonts");
            basic.images = false;
            basic.color = false;
            basic.transparency = false;
            basic.bleed = false;
            basic.pasteboard = false;
            basic.empty = false;
            list.add (basic);
            var print = new PreflightProfile (PRINT);
            print.description = _("Offset printing: 300 ppi pictures, CMYK and spot colours only, 3 mm bleed, 320% total ink");
            print.min_ppi = 300;
            print.error_ppi = 200;
            print.ink_limit = 320;
            print.min_bleed = Units.from_unit (3, "mm");
            print.min_text = 5;
            list.add (print);
            var paper = new PreflightProfile (NEWSPAPER);
            paper.description = _("Newsprint: 200 ppi pictures, 240% total ink, no spot colours");
            paper.min_ppi = 200;
            paper.error_ppi = 120;
            paper.ink_limit = 240;
            paper.allow_spot = false;
            paper.min_text = 6;
            list.add (paper);
            var digital = new PreflightProfile (DIGITAL);
            digital.description = _("Screens: RGB allowed, 144 ppi pictures, no bleed checks, accessibility included");
            digital.min_ppi = 144;
            digital.error_ppi = 72;
            digital.allow_rgb = true;
            digital.bleed = false;
            digital.transparency = false;
            digital.accessibility = true;
            list.add (digital);
            var a11y = new PreflightProfile (ACCESSIBLE);
            a11y.description = _("Accessibility only: alternative text, contrast, table headers, link text and title");
            a11y.links = false;
            a11y.images = false;
            a11y.text = false;
            a11y.fonts = false;
            a11y.color = false;
            a11y.transparency = false;
            a11y.bleed = false;
            a11y.pasteboard = false;
            a11y.empty = false;
            a11y.accessibility = true;
            list.add (a11y);
            foreach (var p in list) p.builtin = true;
            return list;
        }

        public static Gee.ArrayList<PreflightProfile> all (Publication pub) {
            var list = builtins ();
            foreach (var p in pub.preflight_profiles) list.add (p);
            return list;
        }

        public static PreflightProfile find (Publication pub, string name) {
            var list = all (pub);
            foreach (var p in list) if (p.name == name) return p;
            return list[0];
        }

        public static string display_name (string name) {
            switch (name) {
                case BASIC: return _("Basic");
                case PRINT: return _("Commercial Print");
                case DIGITAL: return _("Digital Publishing");
                case NEWSPAPER: return _("Newspaper");
                case ACCESSIBLE: return _("Accessible PDF");
                default: return name;
            }
        }

        public bool allows (IssueKind k) {
            switch (k) {
                case IssueKind.MISSING_LINK:
                case IssueKind.MODIFIED_LINK:
                    return links;
                case IssueKind.LOW_RES:
                case IssueKind.HIGH_RES:
                    return images;
                case IssueKind.OVERSET:
                    return text;
                case IssueKind.MISSING_FONT:
                    return fonts;
                case IssueKind.RGB_IMAGE:
                case IssueKind.RGB_COLOR:
                    return color && !allow_rgb;
                case IssueKind.SPOT_COLOR:
                    return color;
                case IssueKind.INK_LIMIT:
                    return color && ink_limit > 0;
                case IssueKind.TRANSPARENCY:
                    return transparency;
                case IssueKind.OUTSIDE_BLEED:
                case IssueKind.BLEED_SETTING:
                    return bleed;
                case IssueKind.OFF_PAGE:
                    return pasteboard;
                case IssueKind.EMPTY_FRAME:
                case IssueKind.EMPTY_PAGE:
                    return empty;
                case IssueKind.PRINT_TEXT_SIZE:
                    return min_text > 0;
                default:
                    return accessibility;
            }
        }

        public void write (XmlOut x) {
            x.start ("preflight-profile").a ("name", name).a ("description", description);
            x.ai ("links", links ? 1 : 0).ai ("images", images ? 1 : 0).ad ("min-ppi", min_ppi).ad ("error-ppi", error_ppi).ad ("max-ppi", max_ppi);
            x.ai ("text", text ? 1 : 0).ai ("fonts", fonts ? 1 : 0).ad ("min-text", min_text);
            x.ai ("color", color ? 1 : 0).ai ("allow-rgb", allow_rgb ? 1 : 0).ai ("allow-spot", allow_spot ? 1 : 0).ad ("ink-limit", ink_limit);
            x.ai ("transparency", transparency ? 1 : 0).ai ("bleed", bleed ? 1 : 0).ad ("min-bleed", min_bleed);
            x.ai ("pasteboard", pasteboard ? 1 : 0).ai ("empty", empty ? 1 : 0).ai ("accessibility", accessibility ? 1 : 0);
            x.end ();
        }

        public static PreflightProfile read (Xml.Node* n) {
            var p = new PreflightProfile (XmlIn.attr (n, "name") ?? _("Profile"));
            p.description = XmlIn.attr (n, "description") ?? "";
            p.links = XmlIn.int_attr (n, "links", 1) == 1;
            p.images = XmlIn.int_attr (n, "images", 1) == 1;
            p.min_ppi = XmlIn.double_attr (n, "min-ppi", 250);
            p.error_ppi = XmlIn.double_attr (n, "error-ppi", 150);
            p.max_ppi = XmlIn.double_attr (n, "max-ppi", 0);
            p.text = XmlIn.int_attr (n, "text", 1) == 1;
            p.fonts = XmlIn.int_attr (n, "fonts", 1) == 1;
            p.min_text = XmlIn.double_attr (n, "min-text", 0);
            p.color = XmlIn.int_attr (n, "color", 1) == 1;
            p.allow_rgb = XmlIn.int_attr (n, "allow-rgb", 0) == 1;
            p.allow_spot = XmlIn.int_attr (n, "allow-spot", 1) == 1;
            p.ink_limit = XmlIn.double_attr (n, "ink-limit", 0);
            p.transparency = XmlIn.int_attr (n, "transparency", 1) == 1;
            p.bleed = XmlIn.int_attr (n, "bleed", 1) == 1;
            p.min_bleed = XmlIn.double_attr (n, "min-bleed", 0);
            p.pasteboard = XmlIn.int_attr (n, "pasteboard", 1) == 1;
            p.empty = XmlIn.int_attr (n, "empty", 1) == 1;
            p.accessibility = XmlIn.int_attr (n, "accessibility", 0) == 1;
            return p;
        }

        public string to_file_text () {
            var x = new XmlOut ();
            write (x);
            return x.finish ();
        }

        public static PreflightProfile from_file_text (string text) throws Error {
            Xml.Doc* doc = XmlIn.parse (text);
            Xml.Node* root = doc->get_root_element ();
            if (root == null || root->name != "preflight-profile") {
                delete doc;
                throw new FormatError.INVALID (_("This is not a preflight profile"));
            }
            var p = read (root);
            delete doc;
            return p;
        }
    }
}
