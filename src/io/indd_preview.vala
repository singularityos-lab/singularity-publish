namespace Singularity.Apps.Publish {

    public class InddPreview {
        public const uint8[] SIGNATURE = { 0x06, 0x06, 0xED, 0xF5, 0xD8, 0x1D, 0x46, 0xE5, 0xBD, 0x31, 0xEF, 0xE7, 0xFE, 0x74, 0xB7, 0x1D };

        public string title = "";
        public string creator_tool = "";
        public int pages = 0;
        public double width = 0;
        public double height = 0;
        public Gee.ArrayList<Bytes> thumbnails = new Gee.ArrayList<Bytes> ();

        public static bool is_indd (uint8[] d) {
            if (d.length < SIGNATURE.length) return false;
            for (int i = 0; i < SIGNATURE.length; i++) if (d[i] != SIGNATURE[i]) return false;
            return true;
        }

        private static int find (uint8[] d, string needle, int from) {
            uint8[] n = needle.data;
            for (int i = int.max (0, from); i + n.length <= d.length; i++) {
                if (d[i] != n[0]) continue;
                bool ok = true;
                for (int k = 1; k < n.length; k++) if (d[i + k] != n[k]) {
                    ok = false;
                    break;
                }
                if (ok) return i;
            }
            return -1;
        }

        private static string? tag_text (string xml, string tag) {
            int a = xml.index_of ("<" + tag);
            if (a < 0) return null;
            int s = xml.index_of (">", a);
            int e = xml.index_of ("</" + tag + ">", s);
            if (s < 0 || e < 0) return null;
            string inner = xml.substring (s + 1, e - s - 1);
            int li = inner.index_of ("<rdf:li");
            if (li >= 0) {
                int ls = inner.index_of (">", li);
                int le = inner.index_of ("</rdf:li>", ls);
                if (ls >= 0 && le > ls) inner = inner.substring (ls + 1, le - ls - 1);
            }
            return inner.strip ();
        }

        private static string unescape (string s) {
            return s.replace ("&#xA;", "").replace ("&#xa;", "").replace ("&#10;", "").replace ("&amp;", "&").replace ("&lt;", "<").replace ("&gt;", ">").replace ("&quot;", "\"");
        }

        public static InddPreview read (uint8[] d) throws Error {
            if (!is_indd (d)) throw new FormatError.INVALID (_("The file is not an InDesign document."));
            var r = new InddPreview ();
            int a = find (d, "<x:xmpmeta", 0);
            while (a >= 0) {
                int e = find (d, "</x:xmpmeta>", a);
                if (e < 0) break;
                var sb = new StringBuilder ();
                sb.append_len ((string) d[a:e + 12], e + 12 - a);
                string xml = sb.str.make_valid ();
                if (r.title == "") r.title = unescape (tag_text (xml, "dc:title") ?? "");
                if (r.creator_tool == "") r.creator_tool = unescape (tag_text (xml, "xmp:CreatorTool") ?? "");
                string? np = tag_text (xml, "xmpTPg:NPages");
                if (np != null && r.pages == 0) r.pages = int.parse (np);
                int ms = xml.index_of ("<xmpTPg:MaxPageSize");
                if (ms >= 0 && r.width == 0) {
                    string blk = xml.substring (ms);
                    double w = Units.parse_num (tag_text (blk, "stDim:w") ?? "0", 0), h = Units.parse_num (tag_text (blk, "stDim:h") ?? "0", 0);
                    string unit = (tag_text (blk, "stDim:unit") ?? "Points").down ();
                    double f = unit.has_prefix ("mil") ? Units.PT_PER_MM : (unit.has_prefix ("inch") ? 72 : 1);
                    r.width = w * f;
                    r.height = h * f;
                }
                int k = 0;
                while ((k = xml.index_of ("<xmpGImg:image>", k)) >= 0) {
                    int ke = xml.index_of ("</xmpGImg:image>", k);
                    if (ke < 0) break;
                    string b64 = unescape (xml.substring (k + 15, ke - k - 15)).replace ("\n", "").replace ("\r", "").strip ();
                    var img = Base64.decode (b64);
                    if (img.length > 4 && img[0] == 0xFF && img[1] == 0xD8) r.thumbnails.add (new Bytes (img));
                    k = ke;
                }
                a = find (d, "<x:xmpmeta", e);
            }
            return r;
        }

        public Publication to_publication () {
            var s = new DocSettings ();
            if (width > 0 && height > 0) {
                s.width = width;
                s.height = height;
            }
            s.set_margins (0);
            int n = int.max (1, int.max (pages, thumbnails.size > 1 ? thumbnails.size - 1 : thumbnails.size));
            var p = Publication.create (s, n);
            p.meta.title = title;
            var layer = p.layers[0];
            layer.name = _("InDesign Preview");
            var pagethumbs = new Gee.ArrayList<Bytes> ();
            if (thumbnails.size > 1) for (int i = 1; i < thumbnails.size; i++) pagethumbs.add (thumbnails[i]);
            else pagethumbs.add_all (thumbnails);
            for (int i = 0; i < n && i < pagethumbs.size; i++) {
                var im = new ImageFrame ();
                im.id = p.next_id ();
                im.media = p.add_media (pagethumbs[i].get_data (), "indd-page-%d.jpg".printf (i + 1));
                im.x = 0;
                im.y = 0;
                im.w = s.width;
                im.h = s.height;
                im.fit = FitMode.FIT;
                im.locked = true;
                im.layer = layer.id;
                im.alt_text = _("Preview of page %d of the InDesign document").printf (i + 1);
                p.pages[i].items.add (im);
            }
            return p;
        }

        public string note () {
            return _("InDesign documents (.indd) use a closed format. Publish shows the page previews stored inside the file. To edit the layout, open the document in InDesign and choose File, Save a Copy, InDesign Markup (IDML), then open the .idml file here.");
        }

        public static uint8[] synthesize (string title, int pages, double w_pt, double h_pt, Gee.List<Bytes> jpegs) {
            var b = new ByteArray ();
            b.append (SIGNATURE);
            b.append (new uint8[256]);
            var x = new StringBuilder ();
            x.append ("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF><rdf:Description>");
            x.append ("<dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">%s</rdf:li></rdf:Alt></dc:title>".printf (Markup.escape_text (title)));
            x.append ("<xmp:CreatorTool>Adobe InDesign 19.0</xmp:CreatorTool><xmpTPg:NPages>%d</xmpTPg:NPages>".printf (pages));
            x.append ("<xmpTPg:MaxPageSize><stDim:w>%g</stDim:w><stDim:h>%g</stDim:h><stDim:unit>Points</stDim:unit></xmpTPg:MaxPageSize>".printf (w_pt, h_pt));
            foreach (var j in jpegs) x.append ("<xmpGImg:image>%s</xmpGImg:image>".printf (Base64.encode (j.get_data ()).replace ("\n", "&#xA;")));
            x.append ("</rdf:Description></rdf:RDF></x:xmpmeta>");
            b.append (x.str.data);
            b.append (new uint8[128]);
            return b.steal ();
        }
    }
}
