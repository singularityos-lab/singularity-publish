namespace Singularity.Apps.Publish {

    public class SuiteAssets {
        public const string APP = "publish";

        public static Singularity.Assets.Asset from_swatch (Swatch sw) {
            var a = new Singularity.Assets.Asset ();
            a.kind = "color";
            a.name = sw.name;
            a.app = APP;
            var c = Rgba (sw.r, sw.g, sw.b, 1);
            if (sw.model == ColorModel.CMYK) {
                double r = (1 - sw.c) * (1 - sw.k), g = (1 - sw.m) * (1 - sw.k), b = (1 - sw.y) * (1 - sw.k);
                c = Rgba (r, g, b, 1);
                a.set_field ("cmyk", "%s,%s,%s,%s".printf (XmlOut.num (sw.c), XmlOut.num (sw.m), XmlOut.num (sw.y), XmlOut.num (sw.k)));
            }
            a.set_field ("color", c.to_hex ());
            if (sw.spot) a.set_field ("spot", "true");
            return a;
        }

        public static Swatch? to_swatch (Singularity.Assets.Asset a) {
            if (a.kind != "color") return null;
            string cmyk = a.get_field ("cmyk");
            if (cmyk != "") {
                string[] f = cmyk.split (",");
                if (f.length == 4) return new Swatch.cmyk (a.name, Units.parse_num (f[0], 0), Units.parse_num (f[1], 0), Units.parse_num (f[2], 0), Units.parse_num (f[3], 0), a.get_field ("spot") == "true");
            }
            string hex = a.get_field ("color");
            if (hex == "") return null;
            var sw = new Swatch.hex (a.name, hex);
            sw.spot = a.get_field ("spot") == "true";
            return sw;
        }

        public static Singularity.Assets.Asset from_paragraph_style (Publication pub, ParagraphStyle ps) {
            var a = new Singularity.Assets.Asset ();
            a.kind = "paragraph-style";
            a.name = ps.name;
            a.app = APP;
            var p = Publication.create (null, 1);
            p.styles.paragraph.clear ();
            foreach (var s in pub.styles.para_chain (ps.name)) p.styles.paragraph.add (s.clone ());
            foreach (var cs in pub.styles.character) p.styles.character.add (cs.clone ());
            a.set_field ("publish-xml", NativeFormat.to_xml (p));
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (ps.name, pf, cf);
            if (cf.font != null) a.set_field ("font", cf.font);
            a.set_field ("size", XmlOut.num (cf.size));
            return a;
        }

        public static int import_styles (Publication pub, Singularity.Assets.Asset a) throws Error {
            string xml = a.get_field ("publish-xml");
            if (xml == "") return 0;
            var p = NativeFormat.from_xml (xml);
            int n = 0;
            foreach (var ps in p.styles.paragraph) {
                var old = pub.styles.find_paragraph (ps.name);
                if (old != null) pub.styles.paragraph[pub.styles.paragraph.index_of (old)] = ps.clone ();
                else pub.styles.paragraph.add (ps.clone ());
                n++;
            }
            foreach (var cs in p.styles.character) if (pub.styles.find_character (cs.name) == null) pub.styles.character.add (cs.clone ());
            return n;
        }

        public static Singularity.Assets.Asset from_items (Publication pub, string name, Gee.List<Item> items) throws Error {
            var a = new Singularity.Assets.Asset ();
            a.kind = "block";
            a.name = name;
            a.app = APP;
            a.set_field ("publish-block", Base64.encode (BlockPack.pack (pub, items)));
            var im = items.size == 1 ? items[0] as ImageFrame : null;
            if (im != null) a.kind = "logo";
            return a;
        }

        public static Gee.ArrayList<Item> place (Publication pub, Singularity.Assets.Asset a, Gee.List<Item> target) throws Error {
            string data = a.get_field ("publish-block");
            if (data != "") return BlockPack.unpack (pub, Base64.decode (data), target);
            var made = new Gee.ArrayList<Item> ();
            string path = a.get_field ("path");
            if (path != "" && FileUtils.test (path, FileTest.IS_REGULAR)) {
                var im = new ImageFrame ();
                im.id = pub.next_id ();
                im.link = path;
                im.layer = pub.default_layer ().id;
                im.w = 150;
                im.h = 100;
                im.fit = FitMode.FIT;
                im.alt_text = a.name;
                target.add (im);
                made.add (im);
            }
            return made;
        }
    }
}
