namespace Singularity.Apps.Publish {

    public class QuillChunk {
        public string name;
        public int id;
        public uint32 offset;
        public uint32 length;

        public QuillChunk (string name, int id, uint32 offset, uint32 length) {
            this.name = name;
            this.id = id;
            this.offset = offset;
            this.length = length;
        }
    }

    public class PubImage {
        public uint8[] data;
        public string ext;

        public PubImage (uint8[] data, string ext) {
            this.data = data;
            this.ext = ext;
        }
    }

    public class PubReader {
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> stories = new Gee.ArrayList<string> ();
        public Gee.ArrayList<PubImage> images = new Gee.ArrayList<PubImage> ();
        public bool letter = false;
        private int metafiles = 0;
        private int unknown_blips = 0;
        private Gee.HashSet<string> seen = new Gee.HashSet<string> ();

        private static uint16 r16 (uint8[] d, int o) {
            return (uint16) (d[o] | (d[o + 1] << 8));
        }

        private static uint32 r32 (uint8[] d, int o) {
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        public static Gee.ArrayList<QuillChunk> parse_chunks (uint8[] c) throws FormatError {
            var list = new Gee.ArrayList<QuillChunk> ();
            if (c.length < 0x20 || c[0] != 'C' || c[1] != 'H' || c[2] != 'N' || c[3] != 'K' || c[4] != 'I' || c[5] != 'N' || c[6] != 'K') {
                throw new FormatError.INVALID (_("The text index of the publication was not recognised."));
            }
            int n = r16 (c, 0x1A);
            int max = (c.length - 0x20) / 24;
            if (n > max) n = max;
            for (int i = 0; i < n; i++) {
                int o = 0x20 + i * 24;
                var sb = new StringBuilder ();
                for (int k = 0; k < 4; k++) {
                    uint8 ch = c[o + 2 + k];
                    sb.append_c (ch >= 0x20 && ch < 0x7F ? (char) ch : ' ');
                }
                int id = r16 (c, o + 8);
                uint32 off = r32 (c, o + 14);
                uint32 len = r32 (c, o + 18);
                if (off > c.length || len > c.length - off) continue;
                list.add (new QuillChunk (sb.str, id, off, len));
            }
            return list;
        }

        public static string decode_utf16 (uint8[] d, uint32 off, uint32 len) {
            var sb = new StringBuilder ();
            uint32 end = off + (len & ~1u);
            for (uint32 i = off; i + 1 < end && i + 1 < d.length; i += 2) {
                uint u = d[i] | (d[i + 1] << 8);
                if (u >= 0xD800 && u <= 0xDBFF && i + 3 < end) {
                    uint lo = d[i + 2] | (d[i + 3] << 8);
                    if (lo >= 0xDC00 && lo <= 0xDFFF) {
                        sb.append_unichar ((unichar) (0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)));
                        i += 2;
                        continue;
                    }
                }
                if (u >= 0xD800 && u <= 0xDFFF) continue;
                sb.append_unichar ((unichar) u);
            }
            return sb.str;
        }

        public static string clean (string t) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (t.get_next_char (ref i, out c)) {
                if (c == '\r') sb.append_c ('\n');
                else if (c == 0x0B) sb.append_unichar (0x2028);
                else if (c == '\t' || c == '\n') sb.append_unichar (c == '\n' ? 0x2028 : '\t');
                else if (c < 0x20 || c == 0xFFFE || c == 0xFFFF) continue;
                else sb.append_unichar (c);
            }
            string s = sb.str;
            while (s.has_suffix ("\n")) s = s.substring (0, s.length - 1);
            return s;
        }

        private void read_text (CompoundFile cf) {
            string path = "Quill/QuillSub/CONTENTS";
            if (!cf.has (path)) {
                warnings.add (_("No text stream was found; the file may come from an old Publisher version whose text format is not read."));
                return;
            }
            uint8[] c;
            Gee.ArrayList<QuillChunk> chunks;
            try {
                c = cf.read (path);
                chunks = parse_chunks (c);
            } catch (Error e) {
                warnings.add (e.message);
                return;
            }
            QuillChunk? text = null, tcd = null;
            foreach (var ch in chunks) {
                if (ch.name == "TEXT" && text == null) text = ch;
                else if (ch.name == "TCD " && tcd == null) tcd = ch;
            }
            if (text == null) {
                warnings.add (_("The text index has no text chunk."));
                return;
            }
            string all = decode_utf16 (c, text.offset, text.length);
            var lengths = new Gee.ArrayList<int> ();
            if (tcd != null && tcd.length >= 8) {
                uint32 n = r32 (c, (int) tcd.offset);
                uint64 need = 8 + (uint64) n * 8;
                if (n > 0 && n < 100000 && need <= tcd.length) {
                    int base_off = (int) tcd.offset + 8 + (int) n * 4;
                    int64 sum = 0;
                    for (int i = 0; i < n; i++) {
                        uint32 l = r32 (c, base_off + i * 4);
                        lengths.add ((int) l);
                        sum += l;
                    }
                    if (sum > all.char_count () + 1) lengths.clear ();
                }
            }
            if (lengths.size > 1) {
                int pos = 0;
                int total = all.char_count ();
                foreach (int l in lengths) {
                    if (pos >= total) break;
                    int e = int.min (total, pos + l);
                    string part = all.substring (all.index_of_nth_char (pos), all.index_of_nth_char (e) - all.index_of_nth_char (pos));
                    string cl = clean (part);
                    if (cl.strip () != "") stories.add (cl);
                    pos = e;
                }
                if (pos < total) {
                    string cl = clean (all.substring (all.index_of_nth_char (pos)));
                    if (cl.strip () != "") stories.add (cl);
                }
            } else {
                string cl = clean (all);
                if (cl.strip () != "") stories.add (cl);
            }
        }

        private void add_blip (uint8[] d, int start, int len, uint16 type, uint16 inst) {
            int header = (inst & 1) == 1 ? 33 : 17;
            if (type == 0xF01A || type == 0xF01B || type == 0xF01C) {
                metafiles++;
                return;
            }
            if (len <= header) return;
            uint8[] payload = d[start + header:start + len];
            string ext;
            switch (type) {
                case 0xF01D: ext = "jpg"; break;
                case 0xF01E: ext = "png"; break;
                case 0xF029: ext = "tiff"; break;
                case 0xF01F:
                    payload = dib_to_bmp (payload);
                    if (payload.length == 0) {
                        unknown_blips++;
                        return;
                    }
                    ext = "bmp";
                    break;
                default:
                    unknown_blips++;
                    return;
            }
            string key = Checksum.compute_for_data (ChecksumType.SHA1, payload);
            if (seen.contains (key)) return;
            seen.add (key);
            images.add (new PubImage (payload, ext));
        }

        public static uint8[] dib_to_bmp (uint8[] dib) {
            if (dib.length < 40) return new uint8[0];
            uint32 hsize = r32 (dib, 0);
            if (hsize < 12 || hsize > dib.length) return new uint8[0];
            uint32 colors = 0;
            uint32 extra = 0;
            if (hsize >= 40) {
                uint16 bits = r16 (dib, 14);
                uint32 comp = r32 (dib, 16);
                colors = r32 (dib, 32);
                if (colors == 0 && bits <= 8) colors = 1u << bits;
                if (comp == 3 && hsize == 40) extra = 12;
            }
            uint32 offset = 14 + hsize + extra + colors * 4;
            uint32 total = 14 + dib.length;
            var out_data = new uint8[total];
            out_data[0] = 'B';
            out_data[1] = 'M';
            for (int i = 0; i < 4; i++) out_data[2 + i] = (uint8) ((total >> (8 * i)) & 0xFF);
            for (int i = 0; i < 4; i++) out_data[10 + i] = (uint8) ((offset >> (8 * i)) & 0xFF);
            Memory.copy (&out_data[14], dib, dib.length);
            return out_data;
        }

        private void walk_escher (uint8[] d, int start, int end, int depth) {
            int pos = start;
            while (pos + 8 <= end && depth < 32) {
                uint16 verinst = r16 (d, pos);
                uint16 type = r16 (d, pos + 2);
                uint32 len = r32 (d, pos + 4);
                int ver = verinst & 0x0F;
                uint16 inst = verinst >> 4;
                if (type < 0xF000 || len > end - pos - 8) break;
                int body = pos + 8;
                if (ver == 0x0F) walk_escher (d, body, body + (int) len, depth + 1);
                else if (type == 0xF007) {
                    if (len > 36) walk_escher (d, body + 36, body + (int) len, depth + 1);
                } else if ((type >= 0xF018 && type <= 0xF117)) {
                    add_blip (d, body, (int) len, type, inst);
                }
                pos = body + (int) len;
            }
        }

        private void read_images (CompoundFile cf) {
            foreach (string p in cf.streams ()) {
                if (!p.down ().contains ("escher")) continue;
                try {
                    var d = cf.read (p);
                    walk_escher (d, 0, d.length, 0);
                } catch (Error e) {
                    warnings.add (e.message);
                }
            }
            if (metafiles > 0) warnings.add (ngettext ("%d picture is a Windows metafile (EMF, WMF or PICT) and cannot be shown", "%d pictures are Windows metafiles (EMF, WMF or PICT) and cannot be shown", metafiles).printf (metafiles));
            if (unknown_blips > 0) warnings.add (ngettext ("%d picture is in a format that is not read", "%d pictures are in formats that are not read", unknown_blips).printf (unknown_blips));
        }

        public static bool looks_us (string text) {
            int dollars = 0, others = 0;
            unichar c;
            int i = 0;
            while (text.get_next_char (ref i, out c)) {
                if (c == '$') dollars++;
                else if (c == 0x20AC || c == 0xA3) others++;
            }
            return dollars > others;
        }

        public Publication read (uint8[] data) throws Error {
            var cf = new CompoundFile (data);
            bool publisher = cf.has ("Contents") || cf.has ("Quill/QuillSub/CONTENTS");
            if (!publisher) throw new FormatError.INVALID (_("The file is an OLE document but not a Microsoft Publisher publication."));
            var laid = read_layout (cf);
            if (laid != null) return laid;
            read_text (cf);
            read_images (cf);
            if (stories.size == 0 && images.size == 0) throw new FormatError.INVALID (_("No text or pictures could be read from this Publisher file."));
            var all = new StringBuilder ();
            foreach (string s in stories) all.append (s);
            letter = looks_us (all.str);
            warnings.insert (0, _("Publisher layout, fonts and positions are not read; text and pictures were extracted and reflowed"));
            warnings.add (letter ? _("The page size is not read; US Letter was assumed from the text.") : _("The page size is not read; A4 was assumed."));
            var s = new DocSettings ();
            if (letter) {
                s.width = 612;
                s.height = 792;
                s.page_size = "letter";
                s.units = "in";
            }
            s.cmyk = false;
            var pub = Publication.create (s, 0);
            pub.meta.title = "";
            var mr = pub.margin_rect (0);
            foreach (string text in stories) {
                var story = pub.new_story ();
                story.paras.clear ();
                foreach (string line in text.split ("\n")) story.paras.add (new Paragraph.with_text (line, "Body Text"));
                if (story.paras.size == 0) story.paras.add (new Paragraph.with_text ("", "Body Text"));
                var engine = new TextEngine (pub);
                for (int guard = 0; guard < 1000; guard++) {
                    var pg = pub.add_page (-1, "A");
                    pub.add_text_frame (pg.items, mr.x, mr.y, mr.w, mr.h, story);
                    var res = engine.layout_story (story.id);
                    if (!res.overset) break;
                }
            }
            if (images.size > 0) {
                int cols = 2, rows = 3;
                double gap = 12;
                double cw = (mr.w - gap * (cols - 1)) / cols, ch = (mr.h - gap * (rows - 1)) / rows;
                Page? pg = null;
                for (int i = 0; i < images.size; i++) {
                    int k = i % (cols * rows);
                    if (k == 0) pg = pub.add_page (-1, "A");
                    var im = new ImageFrame ();
                    im.id = pub.next_id ();
                    im.layer = pub.default_layer ().id;
                    im.x = mr.x + (k % cols) * (cw + gap);
                    im.y = mr.y + (k / cols) * (ch + gap);
                    im.w = cw;
                    im.h = ch;
                    im.fit = FitMode.FIT;
                    im.media = pub.add_media (images[i].data, "picture." + images[i].ext);
                    pg.items.add (im);
                }
            }
            if (pub.pages.size == 0) pub.add_page (-1, "A");
            return pub;
        }

        private Publication? read_layout (CompoundFile cf) {
            if (!cf.has ("Contents") || !cf.has ("Quill/QuillSub/CONTENTS")) return null;
            try {
                var lay = new PubLayout (cf.read ("Contents"), cf.read ("Quill/QuillSub/CONTENTS"));
                uint8[] esc = cf.has ("Escher/EscherStm") ? cf.read ("Escher/EscherStm") : new uint8[0];
                uint8[] del = cf.has ("Escher/EscherDelayStm") ? cf.read ("Escher/EscherDelayStm") : new uint8[0];
                lay.set_escher (esc, del);
                if (!lay.parse ()) return null;
                var s = new DocSettings ();
                s.width = lay.width;
                s.height = lay.height;
                var match = PageSize.match (s.width, s.height);
                s.page_size = match != null ? match.id : "custom";
                if (s.page_size == "letter" || s.page_size == "legal" || s.page_size == "tabloid") s.units = "in";
                s.cmyk = false;
                var pub = lay.build (s);
                if (lay.placed_text + lay.placed_images + lay.placed_shapes + lay.placed_tables == 0) return null;
                pub.meta.title = "";
                letter = s.page_size == "letter";
                warnings.add_all (lay.warnings);
                return pub;
            } catch (Error e) {
                return null;
            }
        }

        public string notes () {
            return string.joinv ("\n", warnings.to_array ());
        }
    }
}
