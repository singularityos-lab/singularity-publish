namespace Singularity.Apps.Publish {

    public class HeadlessHost : MacroHost {
        public Publication pub;
        public int page = 0;
        public StringBuilder log = new StringBuilder ();

        public HeadlessHost (Publication pub) {
            this.pub = pub;
        }

        public override Publication publication () {
            return pub;
        }

        public override bool run_action (string name, string? param) {
            switch (name) {
                case "add-page":
                    pub.add_page (-1, pub.pages.size > 0 ? pub.pages[pub.pages.size - 1].master : "");
                    return true;
                case "update-toc":
                    if (pub.toc != null) Toc.update (pub, pub.toc);
                    return true;
                case "update-index":
                    if (pub.index != null) IndexBuilder.generate (pub, pub.index);
                    return true;
                case "update-endnotes":
                    Footnotes.update_endnotes (pub, _("Notes"));
                    return true;
                case "update-tables":
                    LinkedTables.update_all (pub, false);
                    return true;
                case "update-styles":
                    TableStyles.update_all (pub);
                    return true;
                default:
                    log.append (_("Action \"%s\" needs the window and was skipped").printf (name) + "\n");
                    return false;
            }
        }

        public override void insert_text (string text) {
            if (page < 0 || page >= pub.pages.size) return;
            foreach (var it in pub.pages[page].items) {
                var t = it as TextFrame;
                if (t == null) continue;
                var st = pub.story (t.story);
                st.insert_text (st.end_pos (), text);
                return;
            }
        }

        public override void go_to_page (int index) {
            page = index.clamp (0, int.max (0, pub.pages.size - 1));
        }

        public override void select_items (Gee.List<Item> items) {
        }

        public override Gee.List<Item> page_items (int index) {
            return index >= 0 && index < pub.pages.size ? pub.pages[index].items : new Gee.ArrayList<Item> ();
        }

        public override void format_chars (string key, string value) {
        }

        public override void apply_style (string name) {
        }

        public override void export_pdf (string path) throws Error {
            new Exporter (pub, new ExportOptions ()).export_pdf (path);
        }

        public override void changed () {
        }

        public override void message (string text) {
            log.append (text + "\n");
        }
    }

    public class Automation {
        public const string USAGE = """Usage: publish-tool DOCUMENT [options]

Options:
  --run FILE            Run a Publish macro (the same language as Tools, Macros)
  --set-text NAME=TEXT  Replace the text of the frame called NAME
  --update              Update table of contents, index, endnotes and linked tables
  --preflight [PROFILE] Print preflight problems; exit status 3 when there are errors
  --export FILE         Export by extension: pdf, epub, idml, sla, html, png or spub
  --pdfx VERSION        With --export FILE.pdf: x1a, x3 or x4
  --save [FILE]         Save the document (or a copy)
""";

        public static Publication open (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            string note;
            var p = Document.load_bytes (data, path, out note);
            p.base_dir = Path.get_dirname (path);
            p.file_name = Path.get_basename (path);
            return p;
        }

        public static void export (Publication p, string path, string pdfx) throws Error {
            string ext = path.down ().substring (path.last_index_of (".") + 1);
            switch (ext) {
                case "pdf":
                    var o = new ExportOptions ();
                    if (pdfx == "x1a") o.color_mode = ColorMode.PDFX1A;
                    else if (pdfx == "x3") o.color_mode = ColorMode.PDFX3;
                    else if (pdfx == "x4") o.color_mode = ColorMode.PDFX4;
                    if (o.color_mode != ColorMode.RGB) o.bleed = true;
                    new Exporter (p, o).export_pdf (path);
                    if (o.color_mode != ColorMode.RGB) {
                        var r = PdfxReport.verify (path, o.color_mode);
                        if (!r.passed) throw new FormatError.INVALID (string.joinv ("\n", r.problems.to_array ()));
                    }
                    break;
                case "epub":
                    EpubExport.export (p, path, false);
                    break;
                case "idml":
                    IdmlWriter.export (p, path);
                    break;
                case "sla":
                    FileUtils.set_contents (path, new SlaWriter (p).write ());
                    break;
                case "html":
                    HtmlExport.export (p, path);
                    break;
                case "png":
                    var ex = new Exporter (p, new ExportOptions ());
                    ex.export_images (Path.get_dirname (path), Path.get_basename (path).replace (".png", ""), "png");
                    break;
                case "spub":
                    FileUtils.set_data (path, NativeFormat.write (p));
                    break;
                default:
                    throw new FormatError.UNSUPPORTED (_("Unknown export format \"%s\"").printf (ext));
            }
        }

        public static int run (string[] args, out string output) {
            var sb = new StringBuilder ();
            output = "";
            if (args.length < 2 || args[1] == "--help") {
                output = USAGE;
                return args.length < 2 ? 1 : 0;
            }
            string doc_path = args[1];
            Publication p;
            try {
                p = open (doc_path);
            } catch (Error e) {
                output = e.message + "\n";
                return 2;
            }
            int status = 0;
            string pdfx = "";
            for (int i = 2; i < args.length; i++) if (args[i] == "--pdfx" && i + 1 < args.length) pdfx = args[i + 1].down ().replace ("pdf/", "").replace ("-", "");
            try {
                for (int i = 2; i < args.length; i++) {
                    string a = args[i];
                    string? next = i + 1 < args.length && !args[i + 1].has_prefix ("--") ? args[i + 1] : null;
                    switch (a) {
                        case "--run":
                            if (next == null) throw new FormatError.INVALID (_("--run needs a file"));
                            string script;
                            FileUtils.get_contents (next, out script);
                            var host = new HeadlessHost (p);
                            new MacroEngine ().run (host, script);
                            sb.append (host.log.str);
                            i++;
                            break;
                        case "--set-text":
                            if (next == null || !next.contains ("=")) throw new FormatError.INVALID (_("--set-text needs NAME=TEXT"));
                            string name = next.substring (0, next.index_of ("="));
                            string text = next.substring (next.index_of ("=") + 1);
                            bool found = false;
                            p.walk ((r) => {
                                var t = r.item as TextFrame;
                                if (t != null && t.name == name) {
                                    var st = p.story (t.story);
                                    string style = st.paras.size > 0 ? st.paras[0].style : StyleSheet.BASIC;
                                    var keep = st.paras.size > 0 && st.paras[0].runs.size > 0 ? st.paras[0].runs[0].clone_format ("") : new Run ("");
                                    st.paras.clear ();
                                    foreach (string line in text.split ("\\n")) {
                                        var para = new Paragraph (style);
                                        var run = keep.clone_format (line);
                                        para.runs.add (run);
                                        st.paras.add (para);
                                    }
                                    found = true;
                                }
                                return true;
                            });
                            if (!found) throw new FormatError.INVALID (_("No frame is called \"%s\"").printf (name));
                            i++;
                            break;
                        case "--update":
                            var h = new HeadlessHost (p);
                            foreach (string act in new string[] { "update-tables", "update-styles", "update-endnotes", "update-toc", "update-index" }) h.run_action (act, null);
                            break;
                        case "--preflight":
                            var pf = new Preflight (p);
                            pf.use_profile (PreflightProfile.find (p, next ?? p.preflight_profile));
                            pf.run ();
                            foreach (var issue in pf.issues) sb.append ("%s\t%s\t%s\n".printf (issue.severity == Severity.ERROR ? "error" : (issue.severity == Severity.WARNING ? "warning" : "note"), issue.page >= 0 ? p.page_label (issue.page) : "-", issue.message));
                            if (pf.count (Severity.ERROR) > 0) status = 3;
                            if (next != null) i++;
                            break;
                        case "--export":
                            if (next == null) throw new FormatError.INVALID (_("--export needs a file"));
                            export (p, next, pdfx);
                            sb.append (_("Exported %s").printf (next) + "\n");
                            i++;
                            break;
                        case "--pdfx":
                            i++;
                            break;
                        case "--save":
                            string target = next ?? doc_path;
                            FileUtils.set_data (target, NativeFormat.write (p));
                            if (next != null) i++;
                            break;
                        default:
                            throw new FormatError.INVALID (_("Unknown option %s").printf (a));
                    }
                }
            } catch (Error e) {
                sb.append (e.message + "\n");
                output = sb.str;
                return 2;
            }
            output = sb.str;
            return status;
        }
    }
}
