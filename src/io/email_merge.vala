namespace Singularity.Apps.Publish {

    public class EmailMessage {
        public string to;
        public string subject;
        public string path;
        public uint8[] data;

        public EmailMessage (string to, string subject, string path, uint8[] data) {
            this.to = to;
            this.subject = subject;
            this.path = path;
            this.data = data;
        }
    }

    public class EmailMerge {
        public static string encode_word (string s) {
            bool ascii = true;
            for (int i = 0; i < s.length; i++) if (s[i] < 0x20 || s[i] > 0x7e) ascii = false;
            if (ascii) return s;
            var sb = new StringBuilder ();
            int i = 0;
            while (i < s.length) {
                int take = 0, bytes = 0;
                unichar c;
                int j = i;
                while (j < s.length && bytes < 36 && s.get_next_char (ref j, out c)) {
                    bytes = j - i;
                    take = j;
                }
                if (take <= i) take = s.length;
                if (sb.len > 0) sb.append ("\r\n ");
                sb.append ("=?UTF-8?B?%s?=".printf (Base64.encode (s.substring (i, take - i).data)));
                i = take;
            }
            return sb.str;
        }

        public static string quoted_printable (string text) {
            var sb = new StringBuilder ();
            int col = 0;
            uint8[] d = text.replace ("\r\n", "\n").replace ("\n", "\r\n").data;
            for (int i = 0; i < d.length; i++) {
                uint8 b = d[i];
                if (b == '\r' && i + 1 < d.length && d[i + 1] == '\n') {
                    sb.append ("\r\n");
                    i++;
                    col = 0;
                    continue;
                }
                string piece;
                bool at_eol = i + 1 >= d.length || d[i + 1] == '\r';
                if ((b >= 33 && b <= 126 && b != '=') || (b == ' ' && !at_eol) || (b == '\t' && !at_eol)) piece = ((char) b).to_string ();
                else piece = "=%02X".printf (b);
                if (col + piece.length > 75) {
                    sb.append ("=\r\n");
                    col = 0;
                }
                sb.append (piece);
                col += piece.length;
            }
            return sb.str;
        }

        public static string base64_lines (uint8[] data) {
            string b = Base64.encode (data);
            var sb = new StringBuilder ();
            for (int i = 0; i < b.length; i += 76) {
                sb.append (b.substring (i, int.min (76, b.length - i)));
                sb.append ("\r\n");
            }
            return sb.str;
        }

        private static string boundary (string tag) {
            return "=_publish_%s_%08x%08x".printf (tag, Random.next_int (), Random.next_int ());
        }

        public static string resolve_placeholders (Publication pub, int record, string text) {
            var sb = new StringBuilder ();
            int i = 0;
            while (i < text.length) {
                int a = text.index_of ("«", i);
                if (a < 0) {
                    sb.append (text.substring (i));
                    break;
                }
                int b = text.index_of ("»", a);
                if (b < 0) {
                    sb.append (text.substring (i));
                    break;
                }
                sb.append (text.substring (i, a - i));
                string field = text.substring (a + "«".length, b - a - "«".length);
                sb.append (pub.merge.value (record, field));
                i = b + "»".length;
            }
            return sb.str;
        }

        public static string plain_text (Publication pub) {
            var sb = new StringBuilder ();
            for (int pi = 0; pi < pub.pages.size; pi++) {
                pub.walk ((r) => {
                    if (r.page != pub.pages[pi]) return true;
                    var t = r.item as TextFrame;
                    if (t != null) {
                        var st = pub.story (t.story);
                        if (st.frames.size > 0 && st.frames[0] == t.id) {
                            var fc = new FieldContext (pub);
                            fc.page_index = pi;
                            foreach (var p in st.paras) {
                                foreach (var run in p.runs) sb.append (run.field != "" ? fc.resolve (run.field) : run.text.replace (" ", "\n"));
                                sb.append ("\n");
                            }
                            sb.append ("\n");
                        }
                    }
                    return true;
                });
            }
            return sb.str.strip () + "\n";
        }

        public static uint8[] compose (string from, string to, string subject, string html, Gee.List<HtmlAsset> parts, string text, uint8[]? pdf, string pdf_name) {
            var sb = new StringBuilder ();
            var now = new DateTime.now_local ();
            sb.append ("Date: %s\r\n".printf (now.format ("%a, %d %b %Y %H:%M:%S %z")));
            if (from != "") sb.append ("From: %s\r\n".printf (from));
            sb.append ("To: %s\r\n".printf (to));
            sb.append ("Subject: %s\r\n".printf (encode_word (subject)));
            sb.append ("Message-ID: <%lld.%08x@publish.singularity>\r\n".printf (get_real_time (), Random.next_int ()));
            sb.append ("MIME-Version: 1.0\r\n");
            sb.append ("X-Unsent: 1\r\n");
            string alt = boundary ("alt");
            string rel = boundary ("rel");
            string mixed = boundary ("mix");
            bool has_pdf = pdf != null && pdf.length > 0;
            if (has_pdf) {
                sb.append ("Content-Type: multipart/mixed; boundary=\"%s\"\r\n\r\n".printf (mixed));
                sb.append ("--%s\r\n".printf (mixed));
            }
            sb.append ("Content-Type: multipart/related; boundary=\"%s\"; type=\"multipart/alternative\"\r\n\r\n".printf (rel));
            sb.append ("--%s\r\n".printf (rel));
            sb.append ("Content-Type: multipart/alternative; boundary=\"%s\"\r\n\r\n".printf (alt));
            sb.append ("--%s\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n".printf (alt));
            sb.append (quoted_printable (text));
            sb.append ("\r\n--%s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n".printf (alt));
            sb.append (quoted_printable (html));
            sb.append ("\r\n--%s--\r\n".printf (alt));
            foreach (var p in parts) {
                sb.append ("--%s\r\n".printf (rel));
                sb.append ("Content-Type: %s; name=\"%s\"\r\nContent-Transfer-Encoding: base64\r\nContent-ID: <%s>\r\nContent-Disposition: inline; filename=\"%s\"\r\n\r\n".printf (p.mime, p.name, p.name, p.name));
                sb.append (base64_lines (p.data));
            }
            sb.append ("--%s--\r\n".printf (rel));
            if (has_pdf) {
                sb.append ("--%s\r\n".printf (mixed));
                sb.append ("Content-Type: application/pdf; name=\"%s\"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename=\"%s\"\r\n\r\n".printf (pdf_name, pdf_name));
                sb.append (base64_lines (pdf));
                sb.append ("--%s--\r\n".printf (mixed));
            }
            return sb.str.data;
        }

        public static string sender (Publication pub) {
            string email = pub.business.get ("email");
            if (email == "") return "";
            string name = pub.business.get ("name");
            if (name == "") name = pub.business.get ("organization");
            return name != "" ? "%s <%s>".printf (encode_word (name), email) : email;
        }

        private static string safe (string s) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) sb.append_unichar (c.isalnum () || c == '@' || c == '.' || c == '-' || c == '_' ? c : '_');
            return sb.str;
        }

        private static uint8[] pdf_of (Publication p) throws Error {
            string tmp = Path.build_filename (Environment.get_tmp_dir (), "publish-mail-%u.pdf".printf (Random.next_int ()));
            try {
                var ex = new Exporter (p, new ExportOptions ());
                ex.export_pdf (tmp);
                uint8[] data;
                FileUtils.get_data (tmp, out data);
                return data;
            } finally {
                FileUtils.unlink (tmp);
            }
        }

        public static Gee.ArrayList<EmailMessage> write_messages (Publication pub, string dir, bool attach_pdf) throws Error {
            var list = new Gee.ArrayList<EmailMessage> ();
            var ms = pub.merge;
            if (!ms.active ()) throw new FormatError.INVALID (_("Choose a data source first."));
            if (ms.email_field == "" || !ms.fields.contains (ms.email_field)) throw new FormatError.INVALID (_("Choose the field that holds the email addresses."));
            DirUtils.create_with_parents (dir, 0700);
            int n = 0;
            foreach (int rec in ms.selected_records ()) {
                string to = ms.value (rec, ms.email_field).strip ();
                if (to == "" || !to.contains ("@")) continue;
                var one = Merge.expand (pub, rec, rec);
                var pages = new Gee.ArrayList<int> ();
                for (int i = 0; i < one.pages.size; i++) pages.add (i);
                Gee.ArrayList<HtmlAsset> parts;
                string html = HtmlExport.render_inline (one, pages, out parts);
                string subject = resolve_placeholders (pub, rec, ms.email_subject != "" ? ms.email_subject : (pub.meta.title != "" ? pub.meta.title : _("Publication")));
                uint8[]? pdf = attach_pdf ? pdf_of (one) : null;
                string base_name = pub.meta.title != "" ? pub.meta.title : _("Publication");
                var data = compose (sender (pub), to, subject, html, parts, plain_text (one), pdf, safe (base_name) + ".pdf");
                n++;
                string path = Path.build_filename (dir, "%03d-%s.eml".printf (n, safe (to)));
                FileUtils.set_data (path, data);
                list.add (new EmailMessage (to, subject, path, data));
            }
            return list;
        }

        public static EmailMessage message_for_page (Publication pub, int page_index, string subject, string to, bool attach_pdf, string dir) throws Error {
            var pages = new Gee.ArrayList<int> ();
            pages.add (page_index);
            Gee.ArrayList<HtmlAsset> parts;
            string html = HtmlExport.render_inline (pub, pages, out parts);
            uint8[]? pdf = null;
            if (attach_pdf) {
                var copy = pub.clone ();
                var keep = copy.pages[page_index];
                copy.pages.clear ();
                copy.pages.add (keep);
                pdf = pdf_of (copy);
            }
            string base_name = pub.meta.title != "" ? pub.meta.title : _("Publication");
            var data = compose (sender (pub), to, subject, html, parts, plain_text (pub), pdf, safe (base_name) + ".pdf");
            DirUtils.create_with_parents (dir, 0700);
            string path = Path.build_filename (dir, "%s.eml".printf (safe (base_name)));
            FileUtils.set_data (path, data);
            return new EmailMessage (to, subject, path, data);
        }
    }
}
