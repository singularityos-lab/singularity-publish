namespace Singularity.Apps.Publish {

    internal class PublishIntents : Object {
        private const string[] SHAPES = { "rect", "ellipse", "line", "polygon", "star" };

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static double num (Json.Object args, string key, double fallback) {
            return args.has_member (key) ? args.get_double_member (key) : fallback;
        }

        private static bool flag (Json.Object args, string key) {
            return args.has_member (key) && args.get_boolean_member (key);
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static string list (string[] values) {
            var b = new StringBuilder ("[");
            for (int i = 0; i < values.length; i++) {
                if (i > 0) b.append (",");
                b.append ("\"").append (values[i]).append ("\"");
            }
            return b.append ("]").str;
        }

        private static double mm (double pt) {
            return Math.round (pt / Units.PT_PER_MM * 100) / 100.0;
        }

        private static double pt (double mm) {
            return mm * Units.PT_PER_MM;
        }

        private static Document need_doc (PublishWindow w) throws Error {
            if (w.doc == null) throw new IOError.FAILED ("no publication is open; create one with publish_new");
            return w.doc;
        }

        private static int page_arg (PublishWindow w, Json.Object args) throws Error {
            var d = need_doc (w);
            if (!args.has_member ("page")) return d.current_page.clamp (0, d.pub.pages.size - 1);
            int p = (int) args.get_int_member ("page") - 1;
            if (p < 0 || p >= d.pub.pages.size) throw new IOError.INVALID_ARGUMENT ("page must be between 1 and %d", d.pub.pages.size);
            return p;
        }

        private static string color_arg (Publication pub, string spec) throws Error {
            if (spec == "" || spec == "none") return ColorRef.NONE;
            if (spec.has_prefix ("#")) {
                Rgba c;
                if (!Rgba.parse_hex (spec, out c)) throw new IOError.INVALID_ARGUMENT ("%s is not a #rrggbb color", spec);
                return spec;
            }
            if (pub.swatch (spec) == null) throw new IOError.NOT_FOUND ("no swatch named %s; publish_outline lists them", spec);
            return ColorRef.swatch (spec);
        }

        private static Item need_item (PublishWindow w, Json.Object args, out int page) throws Error {
            var d = need_doc (w);
            if (!args.has_member ("id")) throw new IOError.INVALID_ARGUMENT ("name the frame by its id from publish_outline");
            var r = d.pub.find_item ((int) args.get_int_member ("id"));
            if (r == null) throw new IOError.NOT_FOUND ("no frame with id %d", (int) args.get_int_member ("id"));
            page = r.page != null ? d.pub.page_index_of (r.page) : -1;
            return r.item;
        }

        private static string kind_id (Item it) {
            if (it is TextFrame) return "text";
            if (it is ImageFrame) return "image";
            if (it is TableItem) return "table";
            if (it is GroupItem) return "group";
            var s = it as ShapeItem;
            return s != null ? s.shape.to_string () : "item";
        }

        private static Json.Object item_info (Publication pub, Item it) {
            var o = new Json.Object ();
            o.set_int_member ("id", it.id);
            o.set_string_member ("kind", kind_id (it));
            if (it.name != "") o.set_string_member ("name", it.name);
            o.set_double_member ("x", mm (it.x));
            o.set_double_member ("y", mm (it.y));
            o.set_double_member ("w", mm (it.w));
            o.set_double_member ("h", mm (it.h));
            if (it.rotation != 0) o.set_double_member ("rotation", it.rotation);
            var t = it as TextFrame;
            if (t != null && pub.stories.has_key (t.story)) {
                var s = pub.stories[t.story];
                string plain = s.plain_text ();
                o.set_string_member ("text", plain.char_count () > 400 ? plain.substring (0, plain.index_of_nth_char (400)) + "…" : plain);
                var styles = new Json.Array ();
                var seen = new Gee.HashSet<string> ();
                foreach (var p in s.paras) if (seen.add (p.style)) styles.add_string_element (p.style);
                o.set_array_member ("paragraph_styles", styles);
            }
            var im = it as ImageFrame;
            if (im != null) o.set_string_member ("image", im.link != "" ? im.link : (im.media != "" ? "embedded" : ""));
            if (it.fill.visible ()) o.set_string_member ("fill", it.fill.color);
            return o;
        }

        private static Json.Node outline (PublishWindow w) {
            var o = new Json.Object ();
            var d = w.doc;
            if (d == null) {
                o.set_boolean_member ("open", false);
                var tpl = new Json.Array ();
                foreach (var t in Templates.all ()) tpl.add_string_element (t.id);
                o.set_array_member ("templates", tpl);
                return obj (o);
            }
            var pub = d.pub;
            o.set_boolean_member ("open", true);
            o.set_string_member ("path", d.path ?? "");
            o.set_boolean_member ("modified", d.modified);
            o.set_boolean_member ("can_undo", d.can_undo);
            o.set_boolean_member ("can_redo", d.can_redo);
            var s = pub.settings;
            var so = new Json.Object ();
            so.set_string_member ("page_size", s.page_size);
            so.set_double_member ("width_mm", mm (s.width));
            so.set_double_member ("height_mm", mm (s.height));
            so.set_boolean_member ("facing", s.facing);
            so.set_double_member ("margin_mm", mm (s.margin_top));
            so.set_int_member ("columns", s.columns);
            o.set_object_member ("settings", so);
            o.set_int_member ("current_page", d.current_page + 1);
            var pages = new Json.Array ();
            for (int i = 0; i < pub.pages.size; i++) {
                var po = new Json.Object ();
                po.set_int_member ("page", i + 1);
                po.set_string_member ("master", pub.pages[i].master);
                var items = new Json.Array ();
                foreach (var it in pub.pages[i].items) items.add_object_element (item_info (pub, it));
                po.set_array_member ("frames", items);
                pages.add_object_element (po);
            }
            o.set_array_member ("pages", pages);
            var ps = new Json.Array ();
            foreach (var st in pub.styles.paragraph) ps.add_string_element (st.name);
            o.set_array_member ("paragraph_styles", ps);
            var sw = new Json.Array ();
            foreach (var x in pub.swatches) sw.add_string_element (x.name);
            o.set_array_member ("swatches", sw);
            return obj (o);
        }

        private static Json.Node new_doc (PublishWindow w, Json.Object args) throws Error {
            if (w.doc != null && w.doc.modified && !flag (args, "discard"))
                throw new IOError.FAILED ("the open publication has unsaved changes; save it first or pass discard");
            string template = text (args, "template");
            Publication p;
            if (template != "") {
                bool known = false;
                foreach (var t in Templates.all ()) if (t.id == template) known = true;
                if (!known) throw new IOError.NOT_FOUND ("no template %s; publish_outline lists them when nothing is open", template);
                p = Templates.build (template);
            } else {
                var s = new DocSettings ();
                string size = text (args, "page_size");
                if (size == "") size = "a4";
                if (size == "custom") {
                    double wmm = num (args, "width_mm", 0), hmm = num (args, "height_mm", 0);
                    if (wmm < 10 || hmm < 10 || wmm > 5000 || hmm > 5000) throw new IOError.INVALID_ARGUMENT ("width_mm and height_mm must be between 10 and 5000");
                    s.width = pt (wmm);
                    s.height = pt (hmm);
                    s.page_size = "custom";
                } else {
                    var ps = PageSize.find (size);
                    if (ps == null) throw new IOError.NOT_FOUND ("unknown page size %s", size);
                    s.width = ps.width;
                    s.height = ps.height;
                    s.page_size = ps.id;
                }
                if (flag (args, "landscape") && s.width < s.height) {
                    double tmp = s.width;
                    s.width = s.height;
                    s.height = tmp;
                }
                s.set_margins (pt (num (args, "margin_mm", 12.7)));
                s.set_bleed (pt (num (args, "bleed_mm", 3)));
                s.facing = flag (args, "facing");
                s.columns = (int) num (args, "columns", 1).clamp (1, 12);
                int pages = (int) num (args, "pages", 1);
                if (pages < 1 || pages > 999) throw new IOError.INVALID_ARGUMENT ("pages must be between 1 and 999");
                p = Templates.blank (s, pages);
            }
            w.load_document (new Document (p));
            return outline (w);
        }

        private static Json.Node open (PublishWindow w, Json.Object args) throws Error {
            string path = text (args, "path");
            if (!FileUtils.test (path, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("no file at %s", path);
            if (w.doc != null && w.doc.modified && !flag (args, "discard"))
                throw new IOError.FAILED ("the open publication has unsaved changes; save it first or pass discard");
            w.load_document (Document.open (path));
            return outline (w);
        }

        private static Json.Node page (PublishWindow w, Json.Object args) throws Error {
            var d = need_doc (w);
            string action = text (args, "action");
            int n = d.pub.pages.size;
            switch (action) {
                case "add":
                    int count = (int) num (args, "count", 1);
                    if (count < 1 || count > 100) throw new IOError.INVALID_ARGUMENT ("count must be between 1 and 100");
                    int at = args.has_member ("page") ? (int) args.get_int_member ("page") - 1 : n;
                    if (at < 0 || at > n) throw new IOError.INVALID_ARGUMENT ("page must be between 1 and %d", n + 1);
                    w.add_pages (at, count, null);
                    break;
                case "delete":
                    if (n <= 1) throw new IOError.FAILED ("a publication needs at least one page");
                    w.delete_page (page_arg (w, args));
                    break;
                case "duplicate":
                    w.duplicate_page (page_arg (w, args));
                    break;
                case "move":
                    int from = page_arg (w, args);
                    int to = (int) num (args, "to", 0) - 1;
                    if (to < 0 || to >= n || to == from) throw new IOError.INVALID_ARGUMENT ("to must be another page between 1 and %d", n);
                    w.move_page (from, to);
                    break;
                case "go":
                    w.go_to_page (page_arg (w, args));
                    break;
                default:
                    throw new IOError.INVALID_ARGUMENT ("action must be add, delete, duplicate, move or go");
            }
            return outline (w);
        }

        private static void set_story_text (Publication pub, TextFrame t, string body, string style) {
            var s = pub.story (t.story);
            string use = style != "" ? style : (s.paras.size > 0 ? s.paras[0].style : StyleSheet.BASIC);
            s.paras.clear ();
            foreach (var line in body.split ("\n")) s.paras.add (new Paragraph.with_text (line, use));
        }

        private static void apply_geometry (Item it, Json.Object args) {
            if (args.has_member ("x")) it.x = pt (args.get_double_member ("x"));
            if (args.has_member ("y")) it.y = pt (args.get_double_member ("y"));
            if (args.has_member ("w")) it.w = pt (args.get_double_member ("w"));
            if (args.has_member ("h")) it.h = pt (args.get_double_member ("h"));
            if (args.has_member ("rotation")) it.rotation = args.get_double_member ("rotation");
            if (args.has_member ("name")) it.name = args.get_string_member ("name");
        }

        private static void check_geometry (Json.Object args) throws Error {
            foreach (var k in new string[] { "w", "h" }) {
                if (args.has_member (k) && (args.get_double_member (k) < 0 || args.get_double_member (k) > 5000))
                    throw new IOError.INVALID_ARGUMENT ("%s must be between 0 and 5000 mm", k);
            }
        }

        private static Json.Node frame (PublishWindow w, Json.Object args) throws Error {
            var d = need_doc (w);
            string action = text (args, "action");
            check_geometry (args);
            switch (action) {
                case "add":
                    string kind = text (args, "kind");
                    int p = page_arg (w, args);
                    var m = d.pub.margin_rect (p);
                    double x = args.has_member ("x") ? pt (num (args, "x", 0)) : m.x;
                    double y = args.has_member ("y") ? pt (num (args, "y", 0)) : m.y;
                    double fw = args.has_member ("w") ? pt (num (args, "w", 0)) : m.w;
                    double fh = args.has_member ("h") ? pt (num (args, "h", 0)) : m.h / 3;
                    string style = text (args, "style");
                    if (style != "" && d.pub.styles.find_paragraph (style) == null) throw new IOError.NOT_FOUND ("no paragraph style %s", style);
                    string fill = args.has_member ("fill") ? color_arg (d.pub, text (args, "fill")) : "";
                    string stroke = args.has_member ("stroke") ? color_arg (d.pub, text (args, "stroke")) : "";
                    Item? made = null;
                    if (kind == "text") {
                        string body = text (args, "text");
                        w.go_to_page (p);
                        w.edit ("Insert Text Frame", () => {
                            var t = d.pub.add_text_frame (d.pub.pages[p].items, x, y, fw, fh);
                            if (body != "" || style != "") set_story_text (d.pub, t, body, style);
                            apply_geometry (t, args);
                            if (fill != "") t.fill = new Fill.solid (fill);
                            made = t;
                        });
                    } else if (kind == "image") {
                        string path = text (args, "path");
                        if (!FileUtils.test (path, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("no image at %s", path);
                        uint8[] data;
                        FileUtils.get_data (path, out data);
                        if (ImageStore.decode (data) == null) throw new IOError.INVALID_DATA ("%s is not an image Publish can read", path);
                        w.go_to_page (p);
                        var im = new ImageFrame ();
                        im.id = d.pub.next_id ();
                        im.x = x;
                        im.y = y;
                        im.w = fw;
                        im.h = fh;
                        im.layer = d.pub.default_layer ().id;
                        w.edit ("Insert Image Frame", () => d.pub.pages[p].items.add (im));
                        w.canvas.select_only (im);
                        w.place_files ({ File.new_for_path (path) });
                        var r = d.pub.find_item (im.id);
                        made = r != null ? r.item : null;
                        var placed = made as ImageFrame;
                        if (placed == null || (placed.link == "" && placed.media == "")) throw new IOError.FAILED ("could not place %s", path);
                    } else if (kind in SHAPES) {
                        var s = new ShapeItem (ShapeKind.parse (kind));
                        s.id = d.pub.next_id ();
                        s.x = x;
                        s.y = y;
                        s.w = fw;
                        s.h = kind == "line" ? 0 : fh;
                        s.layer = d.pub.default_layer ().id;
                        s.stroke = new Stroke.with (stroke != "" ? stroke : ColorRef.BLACK, num (args, "stroke_width", 1));
                        if (kind != "line") s.fill = new Fill.solid (fill != "" ? fill : ColorRef.swatch ("Cyan", 20));
                        if (kind == "star" || kind == "polygon") s.sides = (int) num (args, "sides", 5).clamp (3, 64);
                        w.go_to_page (p);
                        w.edit ("Insert Shape", () => d.pub.pages[p].items.add (s));
                        made = s;
                    } else {
                        throw new IOError.INVALID_ARGUMENT ("kind must be text, image or one of %s", string.joinv (", ", SHAPES));
                    }
                    w.canvas.select_only (made);
                    return obj (item_info (d.pub, made));
                case "update":
                    int page;
                    var it = need_item (w, args, out page);
                    string fill = args.has_member ("fill") ? color_arg (d.pub, text (args, "fill")) : "";
                    string stroke = args.has_member ("stroke") ? color_arg (d.pub, text (args, "stroke")) : "";
                    var t = it as TextFrame;
                    if ((args.has_member ("text") || args.has_member ("style")) && t == null) throw new IOError.INVALID_ARGUMENT ("text and style apply to text frames only");
                    string style = text (args, "style");
                    if (style != "" && d.pub.styles.find_paragraph (style) == null) throw new IOError.NOT_FOUND ("no paragraph style %s", style);
                    int id = it.id;
                    w.edit ("Change Frame", () => {
                        var cur = d.pub.find_item (id).item;
                        apply_geometry (cur, args);
                        if (args.has_member ("fill")) cur.fill = fill == "" ? new Fill () : new Fill.solid (fill);
                        if (args.has_member ("stroke")) cur.stroke = new Stroke.with (stroke, num (args, "stroke_width", cur.stroke.width));
                        var ct = cur as TextFrame;
                        if (ct != null && args.has_member ("text")) set_story_text (d.pub, ct, text (args, "text"), style);
                        else if (ct != null && style != "") foreach (var para in d.pub.story (ct.story).paras) para.style = style;
                    });
                    return obj (item_info (d.pub, d.pub.find_item (id).item));
                case "delete":
                    int page;
                    var it = need_item (w, args, out page);
                    if (page >= 0) w.go_to_page (page);
                    w.canvas.end_edit ();
                    w.canvas.select_only (it);
                    w.run ("delete");
                    if (d.pub.find_item (it.id) != null) throw new IOError.FAILED ("frame %d was not deleted", it.id);
                    return outline (w);
                default:
                    throw new IOError.INVALID_ARGUMENT ("action must be add, update or delete");
            }
        }

        private static Json.Node replace (PublishWindow w, Json.Object args) throws Error {
            need_doc (w);
            string find = text (args, "find");
            if (find == "") throw new IOError.INVALID_ARGUMENT ("find must not be empty");
            var o = new Json.Object ();
            if (!args.has_member ("replace")) {
                int count = 0;
                foreach (var s in w.stories_for_find ()) {
                    string plain = s.plain_text ();
                    int at = 0;
                    while ((at = plain.index_of (find, at)) >= 0) {
                        count++;
                        at += find.length;
                    }
                }
                o.set_int_member ("matches", count);
                return obj (o);
            }
            o.set_string_member ("result", w.replace_all_public (find, text (args, "replace")));
            return obj (o);
        }

        private static Json.Node history (PublishWindow w, Json.Object args) throws Error {
            var d = need_doc (w);
            string action = text (args, "action");
            w.canvas.end_edit ();
            if (action == "undo") {
                if (!d.can_undo) throw new IOError.FAILED ("nothing to undo");
                d.undo ();
            } else if (action == "redo") {
                if (!d.can_redo) throw new IOError.FAILED ("nothing to redo");
                d.redo ();
            } else {
                throw new IOError.INVALID_ARGUMENT ("action must be undo or redo");
            }
            return outline (w);
        }

        private static Json.Node preflight (PublishWindow w) throws Error {
            var d = need_doc (w);
            var pf = new Preflight (d.pub);
            pf.font_check = Preflight.system_has_font;
            var o = new Json.Object ();
            var a = new Json.Array ();
            foreach (var i in pf.run ()) {
                var io = new Json.Object ();
                io.set_string_member ("severity", i.severity == Severity.ERROR ? "error" : (i.severity == Severity.WARNING ? "warning" : "info"));
                io.set_string_member ("category", i.category ());
                io.set_string_member ("message", i.message);
                if (i.page >= 0) io.set_int_member ("page", i.page + 1);
                if (i.item >= 0) io.set_int_member ("id", i.item);
                a.add_object_element (io);
            }
            o.set_int_member ("errors", pf.count (Severity.ERROR));
            o.set_int_member ("warnings", pf.count (Severity.WARNING));
            o.set_array_member ("issues", a);
            return obj (o);
        }

        private static Json.Node save (PublishWindow w, Json.Object args) throws Error {
            var d = need_doc (w);
            string path = text (args, "path");
            if (path == "") path = d.path ?? "";
            if (path == "") throw new IOError.INVALID_ARGUMENT ("the publication has never been saved; pass a path");
            if (!Path.is_absolute (path)) throw new IOError.INVALID_ARGUMENT ("path must be absolute");
            w.canvas.end_edit ();
            d.save_to (path);
            w.update_title ();
            var o = new Json.Object ();
            o.set_string_member ("path", path);
            return obj (o);
        }

        private static Json.Node export (PublishWindow w, Json.Object args) throws Error {
            var d = need_doc (w);
            string path = text (args, "path");
            string format = text (args, "format");
            if (format == "") format = "pdf";
            if (!Path.is_absolute (path)) throw new IOError.INVALID_ARGUMENT ("path must be absolute");
            var opts = new ExportOptions ();
            opts.ranges = text (args, "pages");
            if (args.has_member ("bleed")) opts.bleed = flag (args, "bleed");
            opts.crop_marks = flag (args, "crop_marks");
            w.canvas.end_edit ();
            var o = new Json.Object ();
            var ex = new Exporter (d.pub, opts);
            if (format == "pdf") {
                if (FileUtils.test (path, FileTest.EXISTS) && !flag (args, "overwrite")) throw new IOError.EXISTS ("%s already exists; pass overwrite to replace it", path);
                int n = ex.export_pdf (path);
                o.set_string_member ("path", path);
                o.set_int_member ("pages", n);
                var info = File.new_for_path (path).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                o.set_int_member ("bytes", info.get_size ());
            } else if (format == "png" || format == "jpeg") {
                if (!FileUtils.test (path, FileTest.IS_DIR)) throw new IOError.NOT_FOUND ("for images, path must be an existing folder");
                if (args.has_member ("dpi")) opts.dpi = num (args, "dpi", 150).clamp (36, 1200);
                var files = ex.export_images (path, w.base_name ("page"), format);
                var a = new Json.Array ();
                foreach (var f in files) a.add_string_element (f);
                o.set_array_member ("files", a);
            } else {
                throw new IOError.INVALID_ARGUMENT ("format must be pdf, png or jpeg");
            }
            return obj (o);
        }

        private static Json.Node handle (PublishApp app, string name, Json.Object args) throws Error {
            var w = app.shown_window ();
            switch (name) {
                case "publish_outline": return outline (w);
                case "publish_new": return new_doc (w, args);
                case "publish_open": return open (w, args);
                case "publish_page": return page (w, args);
                case "publish_frame": return frame (w, args);
                case "publish_replace": return replace (w, args);
                case "publish_history": return history (w, args);
                case "publish_preflight": return preflight (w);
                case "publish_save": return save (w, args);
                case "publish_export": return export (w, args);
                default: throw new IOError.NOT_SUPPORTED ("unknown intent %s", name);
            }
        }

        private static void add (PublishApp app, string name, string description, string schema, Singularity.AppIntentRisk risk) {
            app.agent.add_intent (name, description, schema, risk, (args) => handle (app, name, args));
        }

        internal static void install (PublishApp app) {
            string geometry = """"x":{"type":"number","description":"mm from the page's left edge"},"y":{"type":"number","description":"mm from the page's top edge"},"w":{"type":"number","description":"mm"},"h":{"type":"number","description":"mm"},"rotation":{"type":"number"},"name":{"type":"string"}""";
            add (app, "publish_outline", "Describe the open publication: page setup, every page with its frames (ids, kinds, positions in mm, text), paragraph styles and swatches. With nothing open, lists the templates.",
                """{"type":"object","properties":{}}""", Singularity.AppIntentRisk.READ);
            add (app, "publish_new", "Create a publication from a page size or a template.",
                """{"type":"object","properties":{"template":{"type":"string"},"page_size":{"type":"string","description":"a3, a4, a5, a6, b5, letter, ... or custom"},"width_mm":{"type":"number"},"height_mm":{"type":"number"},"landscape":{"type":"boolean"},"pages":{"type":"integer"},"facing":{"type":"boolean"},"margin_mm":{"type":"number"},"bleed_mm":{"type":"number"},"columns":{"type":"integer"},"discard":{"type":"boolean","description":"discard unsaved changes"}}}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "publish_open", "Open a publication file.",
                """{"type":"object","properties":{"path":{"type":"string"},"discard":{"type":"boolean"}},"required":["path"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "publish_page", "Add, delete, duplicate, move or go to pages. Pages are numbered from 1.",
                """{"type":"object","properties":{"action":{"type":"string","enum":["add","delete","duplicate","move","go"]},"page":{"type":"integer"},"count":{"type":"integer"},"to":{"type":"integer"}},"required":["action"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "publish_frame", "Add a text frame, image frame or shape to a page, or update or delete a frame by id. Text replaces the frame's story; new lines start paragraphs. Colors are swatch names or #rrggbb.",
                """{"type":"object","properties":{"action":{"type":"string","enum":["add","update","delete"]},"id":{"type":"integer"},"kind":{"type":"string","enum":""" + list ({ "text", "image", "rect", "ellipse", "line", "polygon", "star" }) + """},"page":{"type":"integer"},""" + geometry + ""","text":{"type":"string"},"style":{"type":"string","description":"paragraph style"},"path":{"type":"string","description":"image file"},"fill":{"type":"string"},"stroke":{"type":"string"},"stroke_width":{"type":"number"},"sides":{"type":"integer"}},"required":["action"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "publish_replace", "Count matches of text across all stories, or replace every match when replace is given.",
                """{"type":"object","properties":{"find":{"type":"string"},"replace":{"type":"string"}},"required":["find"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "publish_history", "Undo or redo the last change.",
                """{"type":"object","properties":{"action":{"type":"string","enum":["undo","redo"]}},"required":["action"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "publish_preflight", "Check the publication for print problems: missing or low resolution images, overset text, missing fonts and more.",
                """{"type":"object","properties":{}}""", Singularity.AppIntentRisk.READ);
            add (app, "publish_save", "Save the publication, to its file or to path.",
                """{"type":"object","properties":{"path":{"type":"string"}}}""", Singularity.AppIntentRisk.IRREVERSIBLE);
            add (app, "publish_export", "Export to PDF, or each page to PNG or JPEG images in a folder.",
                """{"type":"object","properties":{"format":{"type":"string","enum":["pdf","png","jpeg"]},"path":{"type":"string","description":"PDF file, or folder for images"},"pages":{"type":"string","description":"page ranges such as 1-3,5"},"bleed":{"type":"boolean"},"crop_marks":{"type":"boolean"},"dpi":{"type":"number"},"overwrite":{"type":"boolean"}},"required":["path"]}""",
                Singularity.AppIntentRisk.IRREVERSIBLE);
        }
    }
}
