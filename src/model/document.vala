namespace Singularity.Apps.Publish {

    public enum FileKind {
        NATIVE,
        SLA,
        IDML,
        PUB,
        UNKNOWN,
        INDD,
        STORY;

        public static FileKind from_path (string path) {
            string p = path.down ();
            if (p.has_suffix (".sla") || p.has_suffix (".sla.gz")) return SLA;
            if (p.has_suffix (".idml")) return IDML;
            if (p.has_suffix (".pub")) return PUB;
            if (p.has_suffix (".indd")) return INDD;
            if (p.has_suffix ("." + LinkedStory.EXT)) return STORY;
            if (p.has_suffix ("." + NativeFormat.EXT)) return NATIVE;
            return UNKNOWN;
        }

        public static FileKind sniff (uint8[] data) {
            if (InddPreview.is_indd (data)) return INDD;
            if (data.length >= 8 && data[0] == 0xD0 && data[1] == 0xCF && data[2] == 0x11 && data[3] == 0xE0) return PUB;
            if (data.length >= 4 && data[0] == 'P' && data[1] == 'K') {
                try {
                    var zip = new ZipReader (data);
                    if (zip.has ("publication.xml")) return NATIVE;
                    if (zip.has ("designmap.xml")) return IDML;
                } catch (Error e) {
                }
                return UNKNOWN;
            }
            if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) return SLA;
            string head = Bin.head (data, 2048);
            if (head.contains ("<SCRIBUSUTF8") || head.contains ("<SCRIBUS")) return SLA;
            if (head.contains ("<" + LinkedStory.ROOT)) return STORY;
            return UNKNOWN;
        }

        public bool can_save () {
            return this == NATIVE || this == SLA || this == STORY;
        }
    }

    public class UndoStep {
        public string label;
        public Publication state;
        public int page;
        public string key;
        public int64 time;

        public UndoStep (string label, Publication state, int page, string key) {
            this.label = label;
            this.state = state;
            this.page = page;
            this.key = key;
            time = get_monotonic_time ();
        }
    }

    public class Document : Object {
        public Publication pub { get; private set; }
        public string? path = null;
        public FileKind kind = FileKind.NATIVE;
        public bool modified { get; set; default = false; }
        public int current_page = 0;
        public string import_note = "";
        private Gee.ArrayList<UndoStep> undo_stack = new Gee.ArrayList<UndoStep> ();
        private Gee.ArrayList<UndoStep> redo_stack = new Gee.ArrayList<UndoStep> ();
        private const int MAX_UNDO = 150;

        public signal void changed ();
        public signal void replaced ();

        public delegate void EditFunc ();

        public Document (Publication? p = null) {
            pub = p ?? Publication.create ();
        }

        public bool can_undo {
            get { return undo_stack.size > 0; }
        }

        public bool can_redo {
            get { return redo_stack.size > 0; }
        }

        public string undo_label {
            owned get { return undo_stack.size > 0 ? undo_stack[undo_stack.size - 1].label : ""; }
        }

        public string redo_label {
            owned get { return redo_stack.size > 0 ? redo_stack[redo_stack.size - 1].label : ""; }
        }

        public void checkpoint (string label, string key = "") {
            if (key != "" && undo_stack.size > 0) {
                var last = undo_stack[undo_stack.size - 1];
                if (last.key == key && get_monotonic_time () - last.time < 1500000) {
                    last.time = get_monotonic_time ();
                    redo_stack.clear ();
                    return;
                }
            }
            undo_stack.add (new UndoStep (label, pub.clone (), current_page, key));
            if (undo_stack.size > MAX_UNDO) undo_stack.remove_at (0);
            redo_stack.clear ();
        }

        public void drop_checkpoint () {
            if (undo_stack.size > 0) undo_stack.remove_at (undo_stack.size - 1);
        }

        public void touch () {
            modified = true;
            changed ();
        }

        public void edit (string label, EditFunc f, string key = "") {
            checkpoint (label, key);
            f ();
            touch ();
        }

        public void undo () {
            if (undo_stack.size == 0) return;
            var step = undo_stack.remove_at (undo_stack.size - 1);
            redo_stack.add (new UndoStep (step.label, pub, current_page, ""));
            pub = step.state;
            current_page = step.page.clamp (0, int.max (pub.pages.size - 1, 0));
            modified = true;
            replaced ();
            changed ();
        }

        public void redo () {
            if (redo_stack.size == 0) return;
            var step = redo_stack.remove_at (redo_stack.size - 1);
            undo_stack.add (new UndoStep (step.label, pub, current_page, ""));
            pub = step.state;
            current_page = step.page.clamp (0, int.max (pub.pages.size - 1, 0));
            modified = true;
            replaced ();
            changed ();
        }

        public void replace_publication (Publication p) {
            pub = p;
            undo_stack.clear ();
            redo_stack.clear ();
            current_page = 0;
            replaced ();
            changed ();
        }

        public static Publication load_bytes (uint8[] data, string name, out string note) throws Error {
            note = "";
            var k = FileKind.sniff (data);
            if (k == FileKind.UNKNOWN) k = FileKind.from_path (name);
            switch (k) {
                case FileKind.NATIVE:
                    return NativeFormat.read (data);
                case FileKind.SLA:
                    var r = new SlaReader ();
                    var p = r.read (data);
                    note = r.notes ();
                    return p;
                case FileKind.IDML:
                    var r = new IdmlReader ();
                    var p = r.read (data);
                    note = r.notes ();
                    return p;
                case FileKind.STORY:
                    var sb = new StringBuilder ();
                    sb.append_len ((string) data, data.length);
                    note = _("You are editing the text of a story placed in a layout. Save to send the text back; the designer updates it from the Links panel.");
                    return LinkedStory.from_story_xml (sb.str, name);
                case FileKind.INDD:
                    var r = InddPreview.read (data);
                    note = r.note ();
                    return r.to_publication ();
                case FileKind.PUB:
                    var r = new PubReader ();
                    var p = r.read (data);
                    note = r.notes ();
                    return p;
                default:
                    throw new FormatError.INVALID (_("The file is not a publication Publish can open."));
            }
        }

        public static Document open (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            string note;
            var p = load_bytes (data, path, out note);
            p.base_dir = Path.get_dirname (path);
            p.file_name = Path.get_basename (path);
            var d = new Document (p);
            d.import_note = note;
            var k = FileKind.sniff (data);
            if (k == FileKind.UNKNOWN) k = FileKind.from_path (path);
            d.kind = k;
            d.path = k.can_save () ? path : null;
            return d;
        }

        public static uint8[] serialize (Publication p, FileKind kind) throws Error {
            if (kind == FileKind.SLA) return new SlaWriter (p).write ().data;
            if (kind == FileKind.STORY) {
                foreach (var st in p.stories.values) if (st.link_path != "") return LinkedStory.to_xml (p, st).data;
            }
            return NativeFormat.write (p);
        }

        public void save_to (string target) throws Error {
            var now = new DateTime.now_utc ();
            if (pub.meta.created == "") pub.meta.created = now.format ("%Y-%m-%dT%H:%M:%SZ");
            pub.meta.modified = now.format ("%Y-%m-%dT%H:%M:%SZ");
            if (pub.meta.author == "") pub.meta.author = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
            var k = FileKind.from_path (target);
            if (k == FileKind.UNKNOWN || !k.can_save ()) k = FileKind.NATIVE;
            var bytes = serialize (pub, k);
            string tmp = target + ".part";
            FileUtils.set_data (tmp, bytes);
            if (FileUtils.rename (tmp, target) != 0) {
                FileUtils.remove (tmp);
                throw new FileError.FAILED (_("Could not write \"%s\".").printf (target));
            }
            path = target;
            kind = k;
            pub.base_dir = Path.get_dirname (target);
            pub.file_name = Path.get_basename (target);
            modified = false;
            changed ();
        }

        public Page? page {
            owned get { return current_page >= 0 && current_page < pub.pages.size ? pub.pages[current_page] : null; }
        }
    }
}
