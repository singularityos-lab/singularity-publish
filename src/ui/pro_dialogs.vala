using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class ProDialogs {
        public delegate void Done ();

        public static Gdk.Texture texture (Cairo.ImageSurface surf) {
            surf.flush ();
            return Gdk.Texture.for_pixbuf (Exporter.surface_to_pixbuf (surf, true));
        }

        public static string link_label (Publication pub, string link) {
            if (link.has_prefix ("page:")) return _("Page %s").printf (pub.page_label (int.parse (link.substring (5))));
            if (link.has_prefix ("bookmark:")) return _("Bookmark \"%s\"").printf (link.substring (9));
            if (link.has_prefix ("mailto:")) return link.substring (7);
            return link;
        }

        private static Box vbox (AppDialog dlg) {
            return Dialogs.body (dlg);
        }

        public static async void choose_fill_picture (PublishWindow w, Item it) {
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Picture");
            var f = new FileFilter ();
            f.name = _("Images");
            f.add_mime_type ("image/*");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.open (w, null);
                if (file == null || file.get_path () == null) return;
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                if (ImageStore.decode (data) == null) {
                    w.toast (_("\"%s\" is not an image Publish can read").printf (file.get_basename ()));
                    return;
                }
                w.edit (_("Picture Fill"), () => {
                    it.fill.kind = FillKind.PICTURE;
                    it.fill.media = w.doc.pub.add_media (data, file.get_basename ());
                    it.fill.link = "";
                });
                w.inspector.rebuild ();
            } catch (Error e) {
            }
        }

        public static async void export_web (PublishWindow w) {
            var file = yield w.ask_save (_("Export Web Page"), w.base_name (_("Publication")) + ".html", { "html", "htm" }, _("Web Page"));
            if (file == null) return;
            try {
                HtmlExport.export (w.doc.pub, file.get_path ());
                w.toast (_("Exported \"%s\"").printf (file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static async void export_epub (PublishWindow w, bool fixed_layout) {
            var file = yield w.ask_save (fixed_layout ? _("Export Fixed-Layout EPUB") : _("Export EPUB"), w.base_name (_("Publication")) + ".epub", { "epub" }, _("EPUB Book"));
            if (file == null) return;
            try {
                EpubExport.export (w.doc.pub, file.get_path (), fixed_layout);
                w.toast (_("Exported \"%s\"").printf (file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static async void export_site (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Folder for the Web Site");
            dialog.initial_folder = w.default_folder ();
            try {
                var folder = yield dialog.select_folder (w, null);
                if (folder == null) return;
                int n = WebSite.export (w.doc.pub, folder.get_path ());
                var t = new Toast (ngettext ("Published %d page as a web site", "Published %d pages as a web site", n).printf (n));
                t.button_label = _("Open");
                t.button_clicked.connect (() => {
                    try {
                        AppInfo.launch_default_for_uri (folder.get_child ("index.html").get_uri (), w.get_display ().get_app_launch_context ());
                    } catch (Error e) {
                    }
                });
                w.add_toast (t);
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static async void export_xps (PublishWindow w) {
            var file = yield w.ask_save (_("Export XPS Document"), w.base_name (_("Publication")) + ".xps", { "xps" }, _("XPS Document"));
            if (file == null) return;
            try {
                var o = new ExportOptions ();
                o.dpi = 200;
                o.bleed = false;
                int n = XpsExport.export (w.doc.pub, o, file.get_path ());
                w.toast (ngettext ("Exported %d page to \"%s\"", "Exported %d pages to \"%s\"", n).printf (n, file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static async void export_docx (PublishWindow w) {
            var file = yield w.ask_save (_("Export Word Document"), w.base_name (_("Publication")) + ".docx", { "docx" }, _("Word Document"));
            if (file == null) return;
            try {
                DocxWriter.export (w.doc.pub, file.get_path ());
                w.toast (_("Exported \"%s\"").printf (file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static async void export_odg (PublishWindow w) {
            var file = yield w.ask_save (_("Export OpenDocument Drawing"), w.base_name (_("Publication")) + ".odg", { "odg" }, _("OpenDocument Drawing"));
            if (file == null) return;
            try {
                OdgWriter.export (w.doc.pub, file.get_path ());
                w.toast (_("Exported \"%s\"").printf (file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static async void export_idml (PublishWindow w) {
            var file = yield w.ask_save (_("Export InDesign Markup"), w.base_name (_("Publication")) + ".idml", { "idml" }, _("InDesign Markup"));
            if (file == null) return;
            try {
                IdmlWriter.export (w.doc.pub, file.get_path ());
                w.toast (_("Exported \"%s\"").printf (file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }

        public static string mail_dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-publish", "mail");
        }

        public static void send_email (PublishWindow w) {
            var dlg = Dialogs.make (w, _("Send as Email"), 460, 460);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Message"), _("The page becomes the body of an email message that opens in your mail app"));
            var to = new EntryRow (_("To"));
            g.add_row (to);
            var subject = new EntryRow (_("Subject"));
            subject.text = w.doc.pub.meta.title != "" ? w.doc.pub.meta.title : w.base_name (_("Publication"));
            g.add_row (subject);
            var attach = new SwitchRow (_("Attach a PDF"), _("Also send the page as a PDF attachment"), false);
            g.add_row (attach);
            box.append (g);
            Dialogs.footer (dlg, _("Create Message"), () => {
                try {
                    var msg = EmailMerge.message_for_page (w.doc.pub, w.doc.current_page, subject.text, to.text.strip (), attach.switch_btn.active, mail_dir ());
                    try {
                        AppInfo.launch_default_for_uri (File.new_for_path (msg.path).get_uri (), w.get_display ().get_app_launch_context ());
                    } catch (Error e) {
                        w.toast (_("Saved the message as \"%s\"").printf (msg.path));
                    }
                } catch (Error e) {
                    w.show_error (_("Could Not Create the Message"), e.message);
                }
            });
            dlg.open_dialog ();
        }

        private static Publication scratch (Publication src) {
            var p = Publication.create (src.settings.clone (), 1);
            p.styles = src.styles.clone ();
            p.swatches.clear ();
            foreach (var sw in src.swatches) p.swatches.add (sw.clone ());
            p.color_scheme = src.color_scheme;
            p.business = src.business.clone ();
            return p;
        }

        private static Gdk.Texture? item_thumb (Publication p, Item it, int w, int h) {
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            var b = it.bounds ();
            double pad = 6;
            double sc = double.min ((w - 2 * pad) / double.max (1, b.w), (h - 2 * pad) / double.max (1, b.h));
            sc = double.min (sc, 2.5);
            cr.translate ((w - b.w * sc) / 2, (h - b.h * sc) / 2);
            cr.scale (sc, sc);
            cr.translate (-b.x, -b.y);
            bool added = !p.pages[0].items.contains (it);
            if (added) p.pages[0].items.add (it);
            var r = new Renderer (p);
            r.opts.print = true;
            r.draw_item (cr, it, false, 0);
            if (added) p.pages[0].items.remove (it);
            return texture (surf);
        }

        private static Widget card (Gdk.Texture? tex, string name, int w, int h) {
            var box = new Box (Orientation.VERTICAL, 6);
            box.add_css_class ("publish-template-card");
            if (tex != null) {
                var pic = new Picture.for_paintable (tex);
                pic.set_size_request (w, h);
                pic.can_shrink = true;
                box.append (pic);
            }
            var label = new Label (name);
            label.add_css_class ("caption");
            label.wrap = true;
            label.max_width_chars = 18;
            label.justify = Justification.CENTER;
            box.append (label);
            return box;
        }

        public static void building_blocks (PublishWindow w) {
            var dlg = Dialogs.make (w, _("Building Blocks"), 780, 660);
            var outer = new Box (Orientation.VERTICAL, 10);
            outer.margin_start = outer.margin_end = 18;
            outer.margin_top = 6;
            outer.vexpand = true;
            var stack = new Stack ();
            stack.vexpand = true;
            var switcher = new BubbleSwitcher ();
            switcher.halign = Align.CENTER;
            outer.append (switcher);
            var cal = new Box (Orientation.HORIZONTAL, 12);
            cal.halign = Align.CENTER;
            var now = new DateTime.now_local ();
            var month = new SpinButton.with_range (1, 12, 1);
            month.value = BuildingBlocks.calendar_month > 0 ? BuildingBlocks.calendar_month : now.get_month ();
            var year = new SpinButton.with_range (1900, 2200, 1);
            year.value = BuildingBlocks.calendar_year > 0 ? BuildingBlocks.calendar_year : now.get_year ();
            cal.append (new Label (_("Month")));
            cal.append (month);
            cal.append (new Label (_("Year")));
            cal.append (year);
            cal.visible = false;
            outer.append (cal);
            outer.append (stack);
            dlg.content_box.append (outer);
            var p = scratch (w.doc.pub);
            string? chosen = null;
            var flows = new Gee.ArrayList<FlowBox> ();
            Done insert = () => {
                if (chosen == null) return;
                BuildingBlocks.calendar_month = (int) month.value;
                BuildingBlocks.calendar_year = (int) year.value;
                var r = w.default_frame_rect (200, 120);
                GroupItem? g = null;
                w.edit (_("Insert Building Block"), () => {
                    g = BuildingBlocks.build (w.doc.pub, chosen, r.x, r.y);
                    if (g != null) w.canvas.active_list ().add (g);
                });
                if (g != null) {
                    w.canvas.select_only (g);
                    w.pages_panel.refresh_current ();
                }
                dlg.close ();
            };
            foreach (string cat in BuildingBlocks.categories ()) {
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.SINGLE;
                flow.activate_on_single_click = false;
                flow.max_children_per_line = 4;
                flow.min_children_per_line = 2;
                flow.column_spacing = 10;
                flow.row_spacing = 10;
                flow.homogeneous = true;
                flow.valign = Align.START;
                var ids = new Gee.ArrayList<string> ();
                foreach (var b in BuildingBlocks.all ()) {
                    if (b.category != cat) continue;
                    var g = BuildingBlocks.build (p, b.id, 0, 0);
                    var tex = g != null ? item_thumb (p, g, 160, 110) : null;
                    flow.append (card (tex, b.name, 160, 110));
                    ids.add (b.id);
                }
                if (ids.size == 0) {
                    var wp = new WelcomePage ();
                    wp.is_section = true;
                    wp.compact = true;
                    wp.title = _("No Building Blocks Yet");
                    wp.subtitle = _("Save objects from a page to reuse them here");
                    wp.add_action ("x-office-document-template", _("Save Selection as Building Block"), _("Select objects on a page first"), () => {
                        dlg.close ();
                        w.activate_action ("save-building-block", null);
                    });
                    stack.add_titled (wp, cat, cat);
                    continue;
                }
                flow.selected_children_changed.connect (() => {
                    var selc = flow.get_selected_children ();
                    if (selc.length () > 0) chosen = ids[selc.data.get_index ()];
                });
                flow.child_activated.connect ((child) => {
                    chosen = ids[child.get_index ()];
                    insert ();
                });
                if (cat == BuildingBlocks.cat_mine ()) {
                    var gesture = new GestureClick ();
                    gesture.button = Gdk.BUTTON_SECONDARY;
                    gesture.pressed.connect ((n, x, y) => {
                        var child = flow.get_child_at_pos ((int) x, (int) y);
                        if (child == null) return;
                        string id = ids[child.get_index ()];
                        var menu = new ContextMenu (flow);
                        var rect = Gdk.Rectangle ();
                        rect.x = (int) x;
                        rect.y = (int) y;
                        rect.width = rect.height = 1;
                        menu.pointing_to = rect;
                        menu.add_item (_("Delete Building Block"), "user-trash-symbolic", () => {
                            BuildingBlocks.delete_user (id);
                            dlg.close ();
                            building_blocks (w);
                        }, "destructive-action");
                        PublishWindow.popup_menu (menu);
                    });
                    flow.add_controller (gesture);
                }
                flows.add (flow);
                var scroll = new ScrolledWindow ();
                scroll.hscrollbar_policy = PolicyType.NEVER;
                scroll.vexpand = true;
                scroll.child = flow;
                stack.add_titled (scroll, cat, cat);
            }
            switcher.set_stack (stack);
            stack.notify["visible-child-name"].connect (() => cal.visible = stack.visible_child_name == BuildingBlocks.cat_calendars ());
            Dialogs.footer (dlg, _("Insert"), () => insert (), false);
            dlg.open_dialog ();
        }

        public static void save_block (PublishWindow w) {
            if (w.sel ().size == 0) {
                w.toast (_("Select the objects to save as a building block"));
                return;
            }
            var dlg = Dialogs.make (w, _("Save as Building Block"), 420, 280);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Building Block"), _("Saved in My Building Blocks for every publication"));
            var name = new EntryRow (_("Name"));
            name.text = w.sel ().size == 1 && w.sel ()[0].name != "" ? w.sel ()[0].name : _("My Block");
            g.add_row (name);
            box.append (g);
            Dialogs.footer (dlg, _("Save"), () => {
                try {
                    BuildingBlocks.save_user (w.doc.pub, w.sel (), name.text.strip () != "" ? name.text.strip () : _("My Block"));
                    w.toast (_("Saved in My Building Blocks"));
                } catch (Error e) {
                    w.show_error (_("Could Not Save"), e.message);
                }
            });
            dlg.open_dialog ();
        }

        private class WordArtStyle {
            public WarpKind warp;
            public string[] colors;
            public string outline;
            public bool shadow;

            public WordArtStyle (WarpKind warp, string[] colors, string outline, bool shadow) {
                this.warp = warp;
                this.colors = colors;
                this.outline = outline;
                this.shadow = shadow;
            }

            public void apply (WordArtItem wa) {
                wa.warp = warp;
                if (colors.length == 1) wa.fill = new Fill.solid (colors[0]);
                else {
                    var f = new Fill.linear (colors[0], colors[colors.length - 1], 90);
                    f.stops.clear ();
                    for (int i = 0; i < colors.length; i++) f.stops.add (new GradientStop ((double) i / (colors.length - 1), colors[i]));
                    wa.fill = f;
                }
                wa.stroke = outline != "" ? new Stroke.with (outline, 1.2) : new Stroke ();
                wa.shadow.enabled = shadow;
                wa.shadow.dx = wa.shadow.dy = 3;
                wa.shadow.blur = 4;
            }
        }

        private static Gee.ArrayList<WordArtStyle> wordart_styles () {
            var l = new Gee.ArrayList<WordArtStyle> ();
            l.add (new WordArtStyle (WarpKind.NONE, { "#1b1b1b" }, "", false));
            l.add (new WordArtStyle (WarpKind.NONE, { "#1f5fbf", "#6fc3f5" }, "#0d2c5a", false));
            l.add (new WordArtStyle (WarpKind.ARCH_UP, { "#f28c28", "#d7263d" }, "#7a1020", false));
            l.add (new WordArtStyle (WarpKind.WAVE, { "#3aa655" }, "#1a5a2a", true));
            l.add (new WordArtStyle (WarpKind.CIRCLE, { "#7b3fa0" }, "", false));
            l.add (new WordArtStyle (WarpKind.INFLATE, { "#f7d774", "#c8901a" }, "#6b4a0c", true));
            l.add (new WordArtStyle (WarpKind.SLANT_UP, { "#6c757d" }, "", true));
            l.add (new WordArtStyle (WarpKind.DEFLATE, { "#d7263d" }, "#ffffff", false));
            l.add (new WordArtStyle (WarpKind.ARCH_DOWN, { "#0f7c7c" }, "#063c3c", false));
            l.add (new WordArtStyle (WarpKind.TRIANGLE_UP, { "#e53935", "#fdd835", "#43a047", "#1e88e5", "#8e24aa" }, "", false));
            l.add (new WordArtStyle (WarpKind.FADE_RIGHT, { "#111111" }, "", false));
            l.add (new WordArtStyle (WarpKind.CASCADE, { "#c2185b", "#f48fb1" }, "#6a0f35", true));
            return l;
        }

        public static void wordart (PublishWindow w, WordArtItem? existing) {
            var dlg = Dialogs.make (w, existing != null ? _("Edit WordArt") : _("Insert WordArt"), 640, 700);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Text"));
            var text = new EntryRow (_("Text"));
            text.text = existing != null ? existing.text : _("Your Text Here");
            g.add_row (text);
            var font = new EntryRow (_("Font"));
            font.text = existing != null ? existing.font : FontScheme.pick ({ "Noto Serif Display", "Noto Serif", "DejaVu Serif", "Inter" });
            g.add_row (font);
            var bold = new SwitchRow (_("Bold"), null, existing != null ? existing.bold : true);
            g.add_row (bold);
            var italic = new SwitchRow (_("Italic"), null, existing != null && existing.italic);
            g.add_row (italic);
            box.append (g);
            var styles = wordart_styles ();
            int chosen = -1;
            var sg = new PreferencesGroup (_("Style"), existing != null ? _("Leave unselected to keep the current look") : null);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.SINGLE;
            flow.max_children_per_line = 4;
            flow.min_children_per_line = 3;
            flow.column_spacing = 8;
            flow.row_spacing = 8;
            flow.homogeneous = true;
            var p = scratch (w.doc.pub);
            var areas = new Gee.ArrayList<DrawingArea> ();
            for (int i = 0; i < styles.size; i++) {
                var st = styles[i];
                var da = new DrawingArea ();
                da.set_size_request (130, 70);
                da.set_draw_func ((d, cr, ww, hh) => {
                    var wa = new WordArtItem ();
                    wa.text = text.text != "" ? text.text : "WordArt";
                    wa.font = font.text;
                    wa.bold = bold.switch_btn.active;
                    wa.italic = italic.switch_btn.active;
                    wa.w = ww - 10;
                    wa.h = hh - 10;
                    wa.x = 5;
                    wa.y = 5;
                    st.apply (wa);
                    var r = new Renderer (p);
                    r.opts.print = true;
                    r.draw_item (cr, wa, false, 0);
                });
                areas.add (da);
                flow.append (da);
            }
            flow.selected_children_changed.connect (() => {
                var selc = flow.get_selected_children ();
                if (selc.length () > 0) chosen = selc.data.get_index ();
            });
            text.entry_changed.connect (() => {
                foreach (var a in areas) a.queue_draw ();
            });
            font.entry_changed.connect (() => {
                foreach (var a in areas) a.queue_draw ();
            });
            bold.switch_btn.notify["active"].connect (() => {
                foreach (var a in areas) a.queue_draw ();
            });
            italic.switch_btn.notify["active"].connect (() => {
                foreach (var a in areas) a.queue_draw ();
            });
            if (existing == null) flow.select_child (flow.get_child_at_index (1));
            var frame = new Box (Orientation.VERTICAL, 0);
            frame.append (flow);
            sg.add_row (new ActionRow (_("Choose a style"), null));
            box.append (sg);
            box.append (frame);
            Dialogs.footer (dlg, existing != null ? _("Apply") : _("Insert"), () => {
                if (existing != null) {
                    w.edit (_("Edit WordArt"), () => {
                        existing.text = text.text;
                        existing.font = font.text.strip () != "" ? font.text.strip () : "Inter";
                        existing.bold = bold.switch_btn.active;
                        existing.italic = italic.switch_btn.active;
                        if (chosen >= 0) styles[chosen].apply (existing);
                    });
                    w.inspector.rebuild ();
                    return;
                }
                var wa = new WordArtItem ();
                wa.id = w.doc.pub.next_id ();
                wa.layer = w.doc.pub.default_layer ().id;
                wa.text = text.text != "" ? text.text : _("Your Text Here");
                wa.font = font.text.strip () != "" ? font.text.strip () : "Inter";
                wa.bold = bold.switch_btn.active;
                wa.italic = italic.switch_btn.active;
                var r = w.default_frame_rect (300, 90);
                wa.x = r.x;
                wa.y = r.y;
                wa.w = r.w;
                wa.h = r.h;
                styles[chosen >= 0 ? chosen : 1].apply (wa);
                wa.alt_text = wa.text;
                w.add_item (wa, _("Insert WordArt"));
            });
            dlg.open_dialog ();
        }

        public static async void insert_text_file (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Insert Text File");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Text Documents"), { "docx", "odt", "rtf", "txt", "text", "md" }));
            filters.append (PublishWindow.filter (_("Word Documents"), { "docx" }));
            filters.append (PublishWindow.filter (_("OpenDocument Text"), { "odt" }));
            filters.append (PublishWindow.filter (_("Rich Text"), { "rtf" }));
            filters.append (PublishWindow.filter (_("Plain Text"), { "txt", "text", "md" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            File? file = null;
            try {
                file = yield dialog.open (w, null);
            } catch (Error e) {
                return;
            }
            if (file == null || file.get_path () == null) return;
            ImportedText t;
            try {
                t = TextImport.read (file.get_path ());
            } catch (Error e) {
                w.show_error (_("Could Not Insert the File"), e.message);
                return;
            }
            var dlg = Dialogs.make (w, _("Insert Text File"), 440, 320);
            var box = vbox (dlg);
            var g = new PreferencesGroup (file.get_basename (), ngettext ("%d paragraph", "%d paragraphs", t.paragraphs.size).printf (t.paragraphs.size));
            var keep = new SwitchRow (_("Keep Formatting and Styles"), _("Import the document's paragraph and character styles"), t.format != "txt");
            g.add_row (keep);
            box.append (g);
            Dialogs.footer (dlg, _("Insert"), () => place_text (w, t, keep.switch_btn.active));
            dlg.open_dialog ();
        }

        private static void place_text (PublishWindow w, ImportedText t, bool keep) {
            var pub = w.doc.pub;
            var e = w.canvas.edit;
            if (e != null && e.frame != null) {
                TextPos a, b;
                e.ordered (out a, out b);
                w.doc.checkpoint (_("Insert Text File"));
                if (e.has_selection ()) e.story.delete_range (a, b);
                var end = TextImport.insert_into_story (pub, e.story, a, t, keep);
                e.anchor = end;
                e.caret = end;
                w.doc.touch ();
                w.canvas.text_edited ();
                offer_autoflow (w, e.frame);
                return;
            }
            var target = w.single_text_frame ();
            TextFrame? made = null;
            w.edit (_("Insert Text File"), () => {
                if (target != null) {
                    var st = pub.story (target.story);
                    if (st.is_empty ()) {
                        st.paras.clear ();
                        st.paras.add (new Paragraph.with_text (""));
                    }
                    TextImport.insert_into_story (pub, st, st.end_pos (), t, keep);
                    made = target;
                } else {
                    int pi = int.max (0, w.canvas.active_page_index ());
                    var m = pub.margin_rect (pi);
                    made = pub.add_text_frame (w.canvas.active_list (), m.x, m.y, m.w, m.h);
                    made.columns = int.max (1, pub.settings.columns);
                    made.gutter = pub.settings.gutter;
                    var st = pub.story (made.story);
                    TextImport.insert_into_story (pub, st, TextPos (0, 0), t, keep);
                    if (st.paras.size > 1 && st.paras[st.paras.size - 1].length () == 0) st.paras.remove_at (st.paras.size - 1);
                }
            });
            if (made != null) {
                w.canvas.select_only (made);
                w.canvas.invalidate ();
                offer_autoflow (w, made);
            }
        }

        private static void offer_autoflow (PublishWindow w, TextFrame f) {
            var res = w.canvas.cache.story (f.story);
            if (!res.overset) return;
            var dlg = new ConfirmDialog (w.app, _("Autoflow the Text?"), "dialog-question", _("The inserted text does not fit in the frame. Publish can add pages with linked frames until all of it fits."), _("Autoflow"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = w;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) {
                    w.canvas.select_only (f);
                    ProActions.autoflow (w);
                }
            });
            dlg.present ();
        }

        public static async void import_styles (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Import Styles");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Documents with Styles"), { "docx", "odt", NativeFormat.EXT, "sla", "idml" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            File? file = null;
            try {
                file = yield dialog.open (w, null);
            } catch (Error e) {
                return;
            }
            if (file == null || file.get_path () == null) return;
            StyleSheet sheet;
            try {
                string low = file.get_basename ().down ();
                if (low.has_suffix (".docx") || low.has_suffix (".odt")) sheet = TextImport.read (file.get_path ()).styles;
                else sheet = Document.open (file.get_path ()).pub.styles;
            } catch (Error e) {
                w.show_error (_("Could Not Import Styles"), e.message);
                return;
            }
            var dlg = Dialogs.make (w, _("Import Styles"), 440, 340);
            var box = vbox (dlg);
            var g = new PreferencesGroup (file.get_basename (), _("%d paragraph and %d character styles").printf (sheet.paragraph.size, sheet.character.size));
            var over = new SwitchRow (_("Replace Styles with the Same Name"), _("Otherwise existing styles are kept"), true);
            g.add_row (over);
            box.append (g);
            Dialogs.footer (dlg, _("Import"), () => {
                int n = 0;
                w.edit (_("Import Styles"), () => n = TextImport.merge_styles (w.doc.pub, sheet, over.switch_btn.active));
                w.canvas.invalidate ();
                w.styles_panel.rebuild ();
                w.toast (ngettext ("Imported %d style", "Imported %d styles", n).printf (n));
            });
            dlg.open_dialog ();
        }

        public static void hyperlink (PublishWindow w) {
            var pub = w.doc.pub;
            var e = w.canvas.edit;
            bool text_mode = e != null;
            if (!text_mode && w.sel ().size == 0) {
                w.toast (_("Select text or an object for the hyperlink"));
                return;
            }
            string current = "";
            if (text_mode) current = w.current_chars ().link ?? "";
            else current = w.sel ()[0].link;
            var dlg = Dialogs.make (w, _("Hyperlink"), 480, 520);
            var box = vbox (dlg);
            var switcher = new BubbleSwitcher ();
            switcher.halign = Align.CENTER;
            box.append (switcher);
            var stack = new Stack ();
            var web = new PreferencesGroup (_("Web Page"));
            var url = new EntryRow (_("Address"));
            web.add_row (url);
            stack.add_titled (web, "web", _("Web Page"));
            var mail = new PreferencesGroup (_("Email Address"));
            var addr = new EntryRow (_("Email Address"));
            mail.add_row (addr);
            var subj = new EntryRow (_("Subject"));
            mail.add_row (subj);
            stack.add_titled (mail, "mail", _("Email"));
            var place = new PreferencesGroup (_("Place in This Document"));
            string[] pages = new string[pub.pages.size];
            for (int i = 0; i < pub.pages.size; i++) pages[i] = _("Page %s").printf (pub.page_label (i));
            var page_row = new SelectionRow (_("Page"), pages, pages.length > 0 ? pages[0] : "");
            place.add_row (page_row);
            string[] marks = new string[pub.bookmarks.size + 1];
            marks[0] = _("None");
            for (int i = 0; i < pub.bookmarks.size; i++) marks[i + 1] = pub.bookmarks[i].name;
            var mark_row = new SelectionRow (_("Bookmark"), marks, marks[0]);
            place.add_row (mark_row);
            stack.add_titled (place, "place", _("This Document"));
            switcher.set_stack (stack);
            box.append (stack);
            EntryRow? display = null;
            if (text_mode && !e.has_selection ()) {
                var dg = new PreferencesGroup (_("Text"));
                display = new EntryRow (_("Text to Display"));
                dg.add_row (display);
                box.append (dg);
            }
            if (current.has_prefix ("mailto:")) {
                stack.visible_child_name = "mail";
                string rest = current.substring (7);
                int q = rest.index_of ("?subject=");
                addr.text = q >= 0 ? rest.substring (0, q) : rest;
                if (q >= 0) subj.text = Uri.unescape_string (rest.substring (q + 9)) ?? "";
            } else if (current.has_prefix ("page:")) {
                stack.visible_child_name = "place";
                int pg = int.parse (current.substring (5));
                if (pg >= 0 && pg < pages.length) page_row.current_value = pages[pg];
            } else if (current.has_prefix ("bookmark:")) {
                stack.visible_child_name = "place";
                mark_row.current_value = current.substring (9);
            } else {
                url.text = current;
            }
            if (current != "") {
                var rm = new PreferencesGroup (null);
                var rrow = new ActionRow (_("Remove Hyperlink"), link_label (pub, current));
                var rb = new Button.with_label (_("Remove"));
                rb.add_css_class ("destructive-action");
                rb.valign = Align.CENTER;
                rb.clicked.connect (() => {
                    ProActions.remove_link (w);
                    dlg.close ();
                });
                rrow.add_suffix (rb);
                rm.add_row (rrow);
                box.append (rm);
            }
            Dialogs.footer (dlg, _("Apply"), () => {
                string link = "";
                switch (stack.visible_child_name) {
                    case "mail":
                        if (addr.text.strip () == "") return;
                        link = "mailto:" + addr.text.strip ();
                        if (subj.text.strip () != "") link += "?subject=" + Uri.escape_string (subj.text.strip (), null, false);
                        break;
                    case "place":
                        if (mark_row.current_value != _("None")) link = "bookmark:" + mark_row.current_value;
                        else {
                            for (int i = 0; i < pages.length; i++) if (pages[i] == page_row.current_value) link = "page:%d".printf (i);
                        }
                        break;
                    default:
                        string u = url.text.strip ();
                        if (u == "") return;
                        if (!u.contains (":")) u = u.contains ("@") && !u.contains ("/") ? "mailto:" + u : "https://" + u;
                        link = u;
                        break;
                }
                if (link == "") return;
                string fl = link;
                if (text_mode) {
                    bool has_style = pub.styles.find_character (StyleSheet.HYPERLINK) != null;
                    if (!e.has_selection ()) {
                        string shown = display != null && display.text.strip () != "" ? display.text.strip () : link_label (pub, link);
                        w.doc.checkpoint (_("Insert Hyperlink"));
                        var start = e.caret;
                        var tmpl = e.story.format_at (start).clone ();
                        tmpl.fmt.link = fl;
                        if (has_style) tmpl.cstyle = StyleSheet.HYPERLINK;
                        var end = e.story.insert_text (start, shown, tmpl);
                        e.anchor = end;
                        e.caret = end;
                        e.pending = null;
                        w.doc.touch ();
                        w.canvas.text_edited ();
                        return;
                    }
                    w.format_runs (_("Hyperlink"), (r) => {
                        r.fmt.link = fl;
                        if (has_style) r.cstyle = StyleSheet.HYPERLINK;
                    });
                    return;
                }
                var items = new Gee.ArrayList<Item> ();
                items.add_all (w.sel ());
                w.edit (_("Hyperlink"), () => {
                    foreach (var it in items) it.link = fl;
                });
                w.inspector.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void bookmark (PublishWindow w) {
            var pub = w.doc.pub;
            int pi = w.canvas.active_page_index ();
            if (pi < 0) {
                w.toast (_("Bookmarks go on pages, not on master pages"));
                return;
            }
            var dlg = Dialogs.make (w, _("Bookmark"), 420, 300);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("New Bookmark"), _("Marks this spot so hyperlinks and the PDF outline can jump to it"));
            var name = new EntryRow (_("Name"));
            name.text = _("Bookmark %d").printf (pub.bookmarks.size + 1);
            g.add_row (name);
            box.append (g);
            Dialogs.footer (dlg, _("Add"), () => {
                string n = name.text.strip ();
                if (n == "") return;
                double x = 0, y = 0;
                if (w.sel ().size > 0) {
                    var b = w.canvas.selection_bounds ();
                    x = b.x;
                    y = b.y;
                }
                w.edit (_("Add Bookmark"), () => {
                    var old = pub.bookmark (n);
                    if (old != null) pub.bookmarks.remove (old);
                    pub.bookmarks.add (new Bookmark (n, pi, x, y));
                });
                w.toast (_("Added bookmark \"%s\" on page %s").printf (n, pub.page_label (pi)));
            });
            dlg.open_dialog ();
        }

        public static void bookmarks (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Bookmarks"), 460, 520);
            var box = vbox (dlg);
            if (pub.bookmarks.size == 0) {
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.compact = true;
                wp.title = _("No Bookmarks");
                wp.subtitle = _("Bookmarks mark spots in the publication and become PDF bookmarks");
                wp.add_action ("user-bookmarks", _("Add a Bookmark"), _("At the current page or text position"), () => {
                    dlg.close ();
                    bookmark (w);
                });
                box.append (wp);
            } else {
                var g = new PreferencesGroup (null);
                foreach (var b in pub.bookmarks) {
                    var bm = b;
                    var row = new ActionRow (bm.name, _("Page %s").printf (pub.page_label (bm.page)));
                    var go = new Button.with_label (_("Go"));
                    go.valign = Align.CENTER;
                    go.clicked.connect (() => {
                        w.go_to_page (bm.page);
                        dlg.close ();
                    });
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Bookmark");
                    del.clicked.connect (() => {
                        w.edit (_("Delete Bookmark"), () => pub.bookmarks.remove (bm));
                        dlg.close ();
                        bookmarks (w);
                    });
                    row.add_suffix (go);
                    row.add_suffix (del);
                    g.add_row (row);
                }
                box.append (g);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var sp2 = new Box (Orientation.HORIZONTAL, 0);
            sp2.hexpand = true;
            bar.append (sp2);
            bar.append (dlg.add_cancel_button (_("Close")));
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void business (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Business Information"), 520, 760);
            var box = vbox (dlg);
            var sets = BusinessSets.load ();
            var current = pub.business.clone ();
            if (current.set_name == "") current.set_name = sets.size > 0 ? sets[0].set_name : _("Primary Business");
            if (current.is_empty ()) {
                var saved = BusinessSets.find (current.set_name);
                if (saved != null) current = saved.clone ();
            }
            var sg = new PreferencesGroup (_("Information Set"), _("Sets are saved for all publications; fields you insert show the values of the set applied here"));
            string[] names = new string[sets.size + 1];
            for (int i = 0; i < sets.size; i++) names[i] = sets[i].set_name;
            names[sets.size] = _("New Set");
            bool known = false;
            foreach (var s in sets) if (s.set_name == current.set_name) known = true;
            var chooser = new SelectionRow (_("Set"), names, known ? current.set_name : names[sets.size]);
            sg.add_row (chooser);
            var set_name = new EntryRow (_("Set Name"));
            set_name.text = current.set_name;
            sg.add_row (set_name);
            box.append (sg);
            var fg = new PreferencesGroup (_("Details"));
            var rows = new Gee.HashMap<string, EntryRow> ();
            foreach (string k in BusinessInfo.KEYS) {
                var r = new EntryRow (BusinessInfo.label (k));
                r.text = current.get (k).replace ("\n", ", ");
                if (k == "logo") r.tooltip_text = _("Path of a picture file for the logo");
                rows[k] = r;
                fg.add_row (r);
            }
            box.append (fg);
            chooser.selected.connect ((item) => {
                foreach (var s in sets) {
                    if (s.set_name != item) continue;
                    set_name.text = s.set_name;
                    foreach (string k in BusinessInfo.KEYS) rows[k].text = s.get (k).replace ("\n", ", ");
                    return;
                }
                set_name.text = _("Business %d").printf (sets.size + 1);
                foreach (string k in BusinessInfo.KEYS) rows[k].text = "";
            });
            var ag = new PreferencesGroup (null);
            var del = new ActionRow (_("Delete This Set"), null);
            var db = new Button.with_label (_("Delete"));
            db.add_css_class ("destructive-action");
            db.valign = Align.CENTER;
            db.clicked.connect (() => {
                try {
                    BusinessSets.remove (set_name.text.strip ());
                } catch (Error e) {
                }
                dlg.close ();
                business (w);
            });
            del.add_suffix (db);
            ag.add_row (del);
            box.append (ag);
            Dialogs.footer (dlg, _("Update Publication"), () => {
                var info = new BusinessInfo ();
                info.set_name = set_name.text.strip () != "" ? set_name.text.strip () : _("Primary Business");
                foreach (string k in BusinessInfo.KEYS) info.set (k, k == "address" ? rows[k].text.strip ().replace (", ", "\n") : rows[k].text.strip ());
                try {
                    BusinessSets.save (info);
                } catch (Error e) {
                    w.show_error (_("Could Not Save the Set"), e.message);
                }
                w.edit (_("Business Information"), () => pub.business = info);
                w.canvas.invalidate ();
                w.pages_panel.load ();
            });
            dlg.open_dialog ();
        }

        private static void scheme_chips (Cairo.Context cr, string[] colors, int w, int h) {
            int n = int.min (6, colors.length);
            double cw = (double) w / n;
            for (int i = 0; i < n; i++) {
                Rgba c;
                if (!Rgba.parse_hex (colors[i], out c)) continue;
                cr.set_source_rgb (c.r, c.g, c.b);
                cr.rectangle (i * cw, 0, cw, h);
                cr.fill ();
            }
            cr.set_source_rgba (0, 0, 0, 0.2);
            cr.set_line_width (1);
            cr.rectangle (0.5, 0.5, w - 1, h - 1);
            cr.stroke ();
        }

        public static void color_schemes (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Colour Schemes"), 720, 640);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Schemes"), pub.color_scheme != "" ? _("Current scheme: %s").printf (pub.color_scheme) : _("Choose a scheme to recolour everything that uses the scheme colours"));
            box.append (g);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 4;
            flow.min_children_per_line = 2;
            flow.column_spacing = 10;
            flow.row_spacing = 10;
            flow.homogeneous = true;
            foreach (var cs in ColorScheme.all ()) {
                var scheme = cs;
                var b = new Button ();
                b.add_css_class ("flat");
                b.add_css_class ("publish-template-card");
                var inner = new Box (Orientation.VERTICAL, 4);
                var da = new DrawingArea ();
                da.set_size_request (140, 26);
                da.set_draw_func ((d, cr, ww, hh) => scheme_chips (cr, scheme.colors, ww, hh));
                inner.append (da);
                var l = new Label (scheme.custom ? _("%s (custom)").printf (scheme.name) : scheme.name);
                l.add_css_class ("caption");
                if (scheme.name == pub.color_scheme) l.add_css_class ("heading");
                inner.append (l);
                b.child = inner;
                b.clicked.connect (() => {
                    w.edit (_("Colour Scheme"), () => scheme.apply (pub));
                    w.canvas.invalidate ();
                    w.swatches_panel.rebuild ();
                    w.pages_panel.load ();
                    w.toast (_("Applied the %s colour scheme").printf (scheme.name));
                });
                flow.append (b);
            }
            box.append (flow);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var create = new Button.with_label (_("New Colour Scheme…"));
            create.clicked.connect (() => {
                dlg.close ();
                custom_scheme (w);
            });
            bar.append (create);
            var sp = new Box (Orientation.HORIZONTAL, 0);
            sp.hexpand = true;
            bar.append (sp);
            bar.append (dlg.add_cancel_button (_("Close")));
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void custom_scheme (PublishWindow w) {
            var pub = w.doc.pub;
            var base_scheme = ColorScheme.from_publication (pub, _("My Scheme"));
            if (pub.swatch (ColorScheme.MAIN) == null) base_scheme = new ColorScheme (_("My Scheme"), ColorScheme.builtins ()[0].colors);
            var dlg = Dialogs.make (w, _("New Colour Scheme"), 460, 640);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Scheme"));
            var name = new EntryRow (_("Name"));
            name.text = _("My Scheme");
            g.add_row (name);
            box.append (g);
            var cg = new PreferencesGroup (_("Colours"));
            var pickers = new Gee.ArrayList<ColorPickerButton> ();
            for (int i = 0; i < ColorScheme.SLOTS.length; i++) {
                var row = new ActionRow (ColorScheme.slot_label (i));
                var rgba = Gdk.RGBA ();
                rgba.parse (base_scheme.colors[i]);
                var pick = new ColorPickerButton (rgba);
                pick.valign = Align.CENTER;
                row.add_suffix (pick);
                pickers.add (pick);
                cg.add_row (row);
            }
            box.append (cg);
            Dialogs.footer (dlg, _("Save and Apply"), () => {
                string[] cols = new string[ColorScheme.SLOTS.length];
                for (int i = 0; i < cols.length; i++) {
                    var c = pickers[i].color;
                    cols[i] = Rgba (c.red, c.green, c.blue, 1).to_hex ();
                }
                var cs = new ColorScheme (name.text.strip () != "" ? name.text.strip () : _("My Scheme"), cols);
                cs.custom = true;
                try {
                    ColorScheme.save_custom (cs);
                } catch (Error e) {
                    w.show_error (_("Could Not Save the Scheme"), e.message);
                }
                w.edit (_("Colour Scheme"), () => cs.apply (pub));
                w.canvas.invalidate ();
                w.swatches_panel.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void font_schemes (PublishWindow w) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Font Schemes"), 520, 680);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Schemes"), _("A heading font and a body font applied to the styles of the publication"));
            foreach (var fs in FontScheme.all ()) {
                var scheme = fs;
                var row = new ActionRow (scheme.name, null);
                var sample = new Box (Orientation.VERTICAL, 0);
                sample.valign = Align.CENTER;
                var hl = new Label (null);
                hl.set_markup ("<span font_family=\"%s\" size=\"large\" weight=\"bold\">%s</span>".printf (Markup.escape_text (scheme.heading_font ()), Markup.escape_text (scheme.heading_font ())));
                hl.xalign = 1;
                var bl = new Label (null);
                bl.set_markup ("<span font_family=\"%s\">%s</span>".printf (Markup.escape_text (scheme.body_font ()), Markup.escape_text (scheme.body_font ())));
                bl.xalign = 1;
                sample.append (hl);
                sample.append (bl);
                row.add_suffix (sample);
                var apply = new Button.with_label (scheme.name == pub.font_scheme ? _("Applied") : _("Apply"));
                apply.valign = Align.CENTER;
                apply.sensitive = scheme.name != pub.font_scheme;
                apply.clicked.connect (() => {
                    w.edit (_("Font Scheme"), () => scheme.apply (pub));
                    w.canvas.invalidate ();
                    w.styles_panel.rebuild ();
                    dlg.close ();
                    w.toast (_("Applied the %s font scheme").printf (scheme.name));
                });
                row.add_suffix (apply);
                g.add_row (row);
            }
            box.append (g);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var sp = new Box (Orientation.HORIZONTAL, 0);
            sp.hexpand = true;
            bar.append (sp);
            bar.append (dlg.add_cancel_button (_("Close")));
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void alt_text (PublishWindow w) {
            if (w.sel ().size != 1) {
                w.toast (_("Select one object to describe"));
                return;
            }
            var it = w.sel ()[0];
            var dlg = Dialogs.make (w, _("Alternative Text"), 480, 440);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Description"), _("Read by screen readers and used in exported web pages and documents"));
            box.append (g);
            var tv = new TextView ();
            tv.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            tv.buffer.text = it.alt_text;
            tv.top_margin = tv.bottom_margin = tv.left_margin = tv.right_margin = 8;
            var frame = new ScrolledWindow ();
            frame.min_content_height = 120;
            frame.child = tv;
            frame.add_css_class ("card");
            box.append (frame);
            var dg = new PreferencesGroup (null);
            var deco = new SwitchRow (_("Mark as Decorative"), _("The object carries no meaning and is skipped by screen readers"), it.alt_decorative);
            dg.add_row (deco);
            box.append (dg);
            Dialogs.footer (dlg, _("Save"), () => {
                string v = tv.buffer.text.strip ();
                bool d = deco.switch_btn.active;
                w.edit (_("Alternative Text"), () => {
                    it.alt_text = v;
                    it.alt_decorative = d;
                });
                w.inspector.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void border_art (PublishWindow w) {
            if (w.sel ().size == 0) {
                w.toast (_("Select a frame or shape for the border"));
                return;
            }
            var items = new Gee.ArrayList<Item> ();
            items.add_all (w.sel ());
            var dlg = Dialogs.make (w, _("BorderArt"), 640, 640);
            var box = vbox (dlg);
            string chosen = items[0].border_art.design;
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.SINGLE;
            flow.max_children_per_line = 5;
            flow.min_children_per_line = 3;
            flow.column_spacing = 8;
            flow.row_spacing = 8;
            flow.homogeneous = true;
            string[] ids = FxRender.border_ids ();
            var pub = w.doc.pub;
            foreach (string id in ids) {
                string d = id;
                var inner = new Box (Orientation.VERTICAL, 4);
                var da = new DrawingArea ();
                da.set_size_request (96, 70);
                da.set_draw_func ((a, cr, ww, hh) => FxRender.draw_border_preview (cr, pub, d, ww, hh, 12));
                inner.append (da);
                var l = new Label (FxRender.border_label (d));
                l.add_css_class ("caption");
                inner.append (l);
                flow.append (inner);
                if (d == chosen) flow.select_child (flow.get_child_at_index (flow.observe_children ().get_n_items () > 0 ? (int) flow.observe_children ().get_n_items () - 1 : 0));
            }
            flow.selected_children_changed.connect (() => {
                var selc = flow.get_selected_children ();
                if (selc.length () > 0) chosen = ids[selc.data.get_index ()];
            });
            box.append (flow);
            var g = new PreferencesGroup (_("Options"));
            var size = new SpinRow (_("Border Size (pt)"), null, 4, 72, 1, items[0].border_art.size);
            g.add_row (size);
            var crow = new ActionRow (_("Colour"), _("Leave empty for the design's own colours"));
            var sb = new SwatchButton (w, items[0].border_art.color, true);
            crow.add_suffix (sb);
            g.add_row (crow);
            var none = new SwitchRow (_("No Border"), null, items[0].border_art.design == "");
            g.add_row (none);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                string design = none.switch_btn.active ? "" : chosen;
                double sz = size.value;
                string col = sb.spec;
                w.edit (_("BorderArt"), () => {
                    foreach (var it in items) {
                        it.border_art.design = design;
                        it.border_art.size = sz;
                        it.border_art.color = col;
                    }
                });
                w.inspector.rebuild ();
            });
            dlg.open_dialog ();
        }

        public static void thesaurus (PublishWindow w) {
            var langs = Thesaurus.languages ();
            var dlg = Dialogs.make (w, _("Thesaurus"), 460, 620);
            var box = vbox (dlg);
            string word = "";
            var e = w.canvas.edit;
            TextPos wa = TextPos (0, 0), wb = TextPos (0, 0);
            if (e != null) {
                if (e.has_selection ()) {
                    e.ordered (out wa, out wb);
                    word = e.story.plain_range (wa, wb).strip ();
                } else {
                    e.story.word_bounds (e.caret, out wa, out wb);
                    if (wa.offset < wb.offset) word = e.story.plain_range (wa, wb);
                }
            }
            if (langs.size == 0) {
                var sp = new StatusPage ();
                sp.icon_name = "accessories-dictionary";
                sp.title = _("No Thesaurus Installed");
                sp.description = _("Publish reads MyThes thesaurus files (th_LANG.idx and th_LANG.dat) from the mythes folder of your data directories");
                box.append (sp);
                var bar = new Box (Orientation.HORIZONTAL, 8);
                bar.margin_start = bar.margin_end = 18;
                bar.margin_bottom = 16;
                var spc = new Box (Orientation.HORIZONTAL, 0);
                spc.hexpand = true;
                bar.append (spc);
                bar.append (dlg.add_cancel_button (_("Close")));
                dlg.content_box.append (bar);
                dlg.open_dialog ();
                return;
            }
            string lang = w.current_chars ().lang ?? "en";
            string pick = langs[0];
            foreach (string l in langs) if (l.has_prefix (lang)) pick = l;
            var g = new PreferencesGroup (null);
            var lrow = new SelectionRow (_("Language"), langs.to_array (), pick);
            g.add_row (lrow);
            var entry = new EntryRow (_("Look Up"));
            entry.text = word;
            g.add_row (entry);
            box.append (g);
            var results = new Box (Orientation.VERTICAL, 12);
            box.append (results);
            string chosen = "";
            Done lookup = null;
            lookup = () => {
                Widget? c;
                while ((c = results.get_first_child ()) != null) results.remove (c);
                var th = Thesaurus.for_language (lrow.current_value);
                if (th == null) return;
                var entries = th.lookup (entry.text);
                if (entries.size == 0) {
                    var none = new Label (_("No synonyms found"));
                    none.add_css_class ("dim-label");
                    results.append (none);
                    return;
                }
                foreach (var en in entries) {
                    var pg = new PreferencesGroup (en.part != "" ? en.part : null);
                    foreach (string s in en.words) {
                        string syn = s;
                        var row = new ActionRow (syn);
                        var use = new Button.with_label (_("Use"));
                        use.valign = Align.CENTER;
                        use.clicked.connect (() => {
                            chosen = syn;
                            if (e != null && wa.compare (wb) != 0) {
                                e.anchor = wa;
                                e.caret = wb;
                                w.canvas.insert_text (syn);
                                dlg.close ();
                            } else {
                                entry.text = syn;
                                lookup ();
                            }
                        });
                        row.add_suffix (use);
                        pg.add_row (row);
                    }
                    results.append (pg);
                }
            };
            entry.entry_activated.connect (() => lookup ());
            lrow.selected.connect ((item) => lookup ());
            if (word != "") lookup ();
            var bar2 = new Box (Orientation.HORIZONTAL, 8);
            bar2.margin_start = bar2.margin_end = 18;
            bar2.margin_bottom = 16;
            var spc2 = new Box (Orientation.HORIZONTAL, 0);
            spc2.hexpand = true;
            bar2.append (spc2);
            bar2.append (dlg.add_cancel_button (_("Close")));
            dlg.content_box.append (bar2);
            dlg.open_dialog ();
        }

        public static async void import_xml (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Import XML");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("XML Files"), { "xml" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            File? file = null;
            try {
                file = yield dialog.open (w, null);
            } catch (Error e) {
                return;
            }
            if (file == null || file.get_path () == null) return;
            string path = file.get_path ();
            string xml;
            Gee.ArrayList<string> tags;
            try {
                FileUtils.get_contents (path, out xml);
                tags = XmlImport.tags (xml);
            } catch (Error e) {
                w.show_error (_("Could Not Read the XML"), e.message);
                return;
            }
            var pub = w.doc.pub;
            var imp = new XmlImport (pub);
            imp.base_dir = Path.get_dirname (path);
            imp.load_map (pub.xml_map);
            imp.auto_map (tags);
            string[] choices = { _("Text Without a Style"), _("Leave Out"), _("Picture (href or src)") };
            var values = new Gee.ArrayList<string> ();
            values.add ("");
            values.add (XmlImport.IGNORE);
            values.add (XmlImport.IMAGE);
            foreach (var ps in pub.styles.paragraph) {
                choices += _("Paragraph: %s").printf (ps.name);
                values.add (ps.name);
            }
            foreach (var cs in pub.styles.character) {
                choices += _("Character: %s").printf (cs.name);
                values.add ("char:" + cs.name);
            }
            var dlg = Dialogs.make (w, _("Map XML Tags"), 520, 640);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Tags"), _("Each tag becomes a paragraph style, a character style, a picture or is left out; the mapping is kept with the publication"));
            var rows = new Gee.HashMap<string, SelectionRow> ();
            foreach (string t in tags) {
                string cur = imp.map.has_key (t) ? imp.map[t] : "";
                int idx = values.index_of (cur);
                var row = new SelectionRow ("<%s>".printf (t), choices, choices[idx < 0 ? 0 : idx]);
                rows[t] = row;
                g.add_row (row);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Import"), () => {
                foreach (var e in rows.entries) {
                    for (int i = 0; i < choices.length; i++) if (choices[i] == e.value.current_value) {
                        if (values[i] == "") imp.map.unset (e.key);
                        else imp.map[e.key] = values[i];
                    }
                }
                TextFrame? tf = w.single_text_frame ();
                int n = 0;
                w.edit (_("Import XML"), () => {
                    if (tf == null) {
                        int pi = int.max (0, w.canvas.active_page_index ());
                        var m = pub.margin_rect (pi);
                        tf = pub.add_text_frame (w.canvas.active_list (), m.x, m.y, m.w, m.h);
                    }
                    try {
                        n = imp.run (xml, pub.story (tf.story));
                    } catch (Error e) {
                    }
                });
                w.canvas.invalidate ();
                w.toast (ngettext ("Imported %d paragraph", "Imported %d paragraphs", n).printf (n));
            });
            dlg.open_dialog ();
        }

        public static async void place_spreadsheet (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Place a Spreadsheet as a Linked Table");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Spreadsheets"), { "xlsx", "ods" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            File? file = null;
            try {
                file = yield dialog.open (w, null);
            } catch (Error e) {
                return;
            }
            if (file == null || file.get_path () == null) return;
            string path = file.get_path ();
            Gee.ArrayList<string> sheets;
            try {
                sheets = SheetReader.sheet_names (path);
            } catch (Error e) {
                w.show_error (_("Could Not Read the Spreadsheet"), e.message);
                return;
            }
            var dlg = Dialogs.make (w, _("Linked Table"), 440, 320);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Sheet"), _("The table updates when the spreadsheet changes; formatting you add in Publish is kept"));
            string[] names = sheets.size > 0 ? sheets.to_array () : new string[] { _("Sheet 1") };
            var pick = new SelectionRow (_("Sheet"), names, names[0]);
            g.add_row (pick);
            box.append (g);
            Dialogs.footer (dlg, _("Place"), () => {
                int idx = 0;
                for (int i = 0; i < names.length; i++) if (names[i] == pick.current_value) idx = i;
                try {
                    int pi = int.max (0, w.canvas.active_page_index ());
                    var m = w.doc.pub.margin_rect (pi);
                    var t = LinkedTables.create (w.doc.pub, path, idx, m.x, m.y, m.w);
                    w.add_item (t, _("Place Linked Table"));
                } catch (Error e) {
                    w.show_error (_("Could Not Place the Table"), e.message);
                }
            });
            dlg.open_dialog ();
        }

        public static async void merge_sheet (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Use a Spreadsheet");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Spreadsheets"), { "xlsx", "ods", "csv", "tsv" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            File? file = null;
            try {
                file = yield dialog.open (w, null);
            } catch (Error e) {
                return;
            }
            if (file == null || file.get_path () == null) return;
            string path = file.get_path ();
            if (path.down ().has_suffix (".csv") || path.down ().has_suffix (".tsv")) {
                w.merge_panel.load_csv (path);
                return;
            }
            Gee.ArrayList<string> sheets;
            try {
                sheets = SheetReader.sheet_names (path);
            } catch (Error e) {
                w.show_error (_("Could Not Read the Spreadsheet"), e.message);
                return;
            }
            var dlg = Dialogs.make (w, _("Use a Spreadsheet"), 440, 340);
            var box = vbox (dlg);
            var g = new PreferencesGroup (file.get_basename ());
            var sheet = new SelectionRow (_("Sheet"), sheets.to_array (), sheets.size > 0 ? sheets[0] : "");
            g.add_row (sheet);
            var header = new SwitchRow (_("First Row Has Field Names"), null, true);
            g.add_row (header);
            box.append (g);
            Dialogs.footer (dlg, _("Use"), () => {
                try {
                    int idx = sheets.index_of (sheet.current_value);
                    var t = SheetReader.read (path, int.max (0, idx), header.switch_btn.active);
                    w.edit (_("Use Spreadsheet"), () => Merge.set_source (w.doc.pub, t, "sheet", path));
                    w.toggle_panel ("merge", true);
                    w.merge_panel.rebuild ();
                    w.toast (ngettext ("%d recipient", "%d recipients", t.records.size).printf (t.records.size));
                } catch (Error e) {
                    w.show_error (_("Could Not Read the Spreadsheet"), e.message);
                }
            });
            dlg.open_dialog ();
        }

        public static async void merge_database (PublishWindow w) {
            if (!DbReader.available ()) {
                w.show_error (_("Databases Are Not Available"), _("This build of Publish was made without SQLite support."));
                return;
            }
            var dialog = new FileDialog ();
            dialog.title = _("Use a Database");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Databases"), { "sdb", "sqlite", "sqlite3", "db" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            File? file = null;
            try {
                file = yield dialog.open (w, null);
            } catch (Error e) {
                return;
            }
            if (file == null || file.get_path () == null) return;
            string path = file.get_path ();
            Gee.ArrayList<string> tables;
            try {
                tables = DbReader.tables (path);
            } catch (Error e) {
                w.show_error (_("Could Not Open the Database"), e.message);
                return;
            }
            var dlg = Dialogs.make (w, _("Use a Database"), 480, 400);
            var box = vbox (dlg);
            var g = new PreferencesGroup (file.get_basename (), _("Choose a table or view, or type a query that selects the recipients"));
            var table = new SelectionRow (_("Table"), tables.to_array (), tables.size > 0 ? tables[0] : "");
            g.add_row (table);
            var query = new EntryRow (_("Query (optional)"));
            query.tooltip_text = _("A SELECT statement, for example SELECT * FROM people WHERE city = 'Rome'");
            g.add_row (query);
            box.append (g);
            Dialogs.footer (dlg, _("Use"), () => {
                try {
                    DataTable t;
                    if (query.text.strip () != "") t = DbReader.query (path, query.text.strip ());
                    else t = DbReader.read_table (path, table.current_value);
                    w.edit (_("Use Database"), () => Merge.set_source (w.doc.pub, t, "database", path));
                    w.toggle_panel ("merge", true);
                    w.merge_panel.rebuild ();
                    w.toast (ngettext ("%d recipient", "%d recipients", t.records.size).printf (t.records.size));
                } catch (Error e) {
                    w.show_error (_("Could Not Read the Database"), e.message);
                }
            });
            dlg.open_dialog ();
        }

        public static async void merge_email (PublishWindow w) {
            var pub = w.doc.pub;
            if (!pub.merge.active ()) {
                w.toast (_("Choose a data source first"));
                return;
            }
            bool lettere = yield LettereMail.available ();
            var dlg = Dialogs.make (w, _("Merge to Email"), 520, 620);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Messages"), _("One message per recipient, with the merged publication as the body"));
            string[] fields = pub.merge.fields.to_array ();
            string guess = pub.merge.email_field;
            if (guess == "") foreach (string f in fields) if (f.down ().contains ("mail")) guess = f;
            if (guess == "" && fields.length > 0) guess = fields[0];
            var field = new SelectionRow (_("Email Address Field"), fields, guess);
            g.add_row (field);
            var subject = new EntryRow (_("Subject"));
            subject.text = pub.merge.email_subject != "" ? pub.merge.email_subject : (pub.meta.title != "" ? pub.meta.title : _("Publication"));
            subject.tooltip_text = _("Merge fields such as «Name» are replaced for each recipient");
            g.add_row (subject);
            var attach = new SwitchRow (_("Attach a PDF"), _("Each message also carries the merged publication as a PDF"), false);
            g.add_row (attach);
            int count = pub.merge.selected_records ().size;
            g.add_row (new ActionRow (_("Recipients"), ngettext ("%d selected recipient", "%d selected recipients", count).printf (count)));
            box.append (g);
            var dg = new PreferencesGroup (_("Delivery"));
            string save_label = _("Save the Messages in a Folder");
            string send_label = _("Send with Lettere");
            string[] choices = {};
            if (lettere) choices += send_label;
            choices += save_label;
            var how = new SelectionRow (_("Method"), choices, choices[0]);
            how.subtitle = lettere ? _("Lettere asks which account to send from and keeps a copy in Sent") : _("Install Lettere to send the messages directly");
            dg.add_row (how);
            box.append (dg);
            Dialogs.footer (dlg, _("Continue"), () => {
                string f = field.current_value, sj = subject.text;
                string dir = Path.build_filename (mail_dir (), "merge-%s".printf (new DateTime.now_local ().format ("%Y%m%d-%H%M%S")));
                bool att = attach.switch_btn.active;
                w.edit (_("Merge to Email"), () => {
                    pub.merge.email_field = f;
                    pub.merge.email_subject = sj;
                });
                Gee.ArrayList<EmailMessage> list;
                try {
                    list = EmailMerge.write_messages (pub, dir, att);
                } catch (Error e) {
                    w.show_error (_("Could Not Create the Messages"), e.message);
                    return;
                }
                if (list.size == 0) {
                    w.toast (_("No selected record has an email address"));
                    return;
                }
                if (how.current_value != send_label) {
                    var t = new Toast (ngettext ("Created %d message ready to send", "Created %d messages ready to send", list.size).printf (list.size));
                    t.button_label = _("Open Folder");
                    t.button_clicked.connect (() => {
                        try {
                            AppInfo.launch_default_for_uri (File.new_for_path (dir).get_uri (), w.get_display ().get_app_launch_context ());
                        } catch (Error e) {
                        }
                    });
                    w.add_toast (t);
                    return;
                }
                mail_preview (w, list);
            }, true);
            dlg.open_dialog ();
        }

        private static void mail_preview (PublishWindow w, Gee.ArrayList<EmailMessage> list) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Check Before Sending"), 520, 640);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("First Message"), ngettext ("%d message will be sent through Lettere", "%d messages will be sent through Lettere", list.size).printf (list.size));
            g.add_row (new ActionRow (_("To"), list[0].to));
            g.add_row (new ActionRow (_("Subject"), list[0].subject));
            box.append (g);
            var recs = pub.merge.selected_records ();
            if (recs.size > 0) {
                var one = Merge.expand (pub, recs[0], recs[0]);
                if (one.pages.size > 0) {
                    double sc = double.min (440 / one.settings.width, 320 / one.settings.height);
                    int pw = int.max (1, (int) (one.settings.width * sc)), ph = int.max (1, (int) (one.settings.height * sc));
                    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
                    var cr = new Cairo.Context (surf);
                    cr.scale (sc, sc);
                    var r = new Renderer (one);
                    r.opts.print = true;
                    r.opts.placeholders = false;
                    r.draw_page (cr, 0);
                    surf.flush ();
                    var pic = new Picture.for_paintable (texture (surf));
                    pic.set_size_request (pw, ph);
                    pic.halign = Align.CENTER;
                    pic.can_shrink = true;
                    pic.alternative_text = _("Preview of the first message");
                    box.append (pic);
                }
            }
            Dialogs.footer (dlg, ngettext ("Send %d Message", "Send %d Messages", list.size).printf (list.size), () => {
                mail_send.begin (w, list);
            }, true);
            dlg.open_dialog ();
        }

        private static async void mail_send (PublishWindow w, Gee.ArrayList<EmailMessage> list) {
            var dlg = Dialogs.make (w, _("Sending"), 460, 260);
            var box = vbox (dlg);
            var label = new Label (_("Waiting for Lettere…"));
            label.xalign = 0;
            label.wrap = true;
            box.append (label);
            var bar = new ProgressBar ();
            bar.margin_top = 12;
            box.append (bar);
            var cancel = new MailStop ();
            var stop = new Button.with_label (_("Stop"));
            stop.halign = Align.END;
            stop.margin_top = 12;
            stop.clicked.connect (() => cancel.stop ());
            box.append (stop);
            dlg.open_dialog ();
            Gee.ArrayList<MailOutcome>? outcomes = null;
            string failure = "";
            try {
                outcomes = yield LettereMail.send_all (list, "", (done, total, last) => {
                    bar.fraction = done / (double) total;
                    label.label = _("Sent %d of %d").printf (done, total);
                }, cancel);
            } catch (Error e) {
                failure = e.message;
            }
            dlg.close ();
            if (outcomes == null) {
                w.show_error (_("Could Not Send the Messages"), failure);
                return;
            }
            mail_report (w, list, outcomes);
        }

        private static void mail_report (PublishWindow w, Gee.ArrayList<EmailMessage> list, Gee.ArrayList<MailOutcome> outcomes) {
            int ok = 0;
            foreach (var o in outcomes) if (o.sent) ok++;
            var dlg = Dialogs.make (w, _("Sending Report"), 520, 560);
            var box = vbox (dlg);
            var g = new PreferencesGroup (_("Result"), _("Sent %d of %d messages").printf (ok, list.size));
            if (outcomes.size < list.size) g.add_row (new ActionRow (_("Stopped"), ngettext ("%d message was not sent", "%d messages were not sent", list.size - outcomes.size).printf (list.size - outcomes.size)));
            box.append (g);
            var failed = new Gee.ArrayList<EmailMessage> ();
            for (int i = 0; i < outcomes.size; i++) if (!outcomes[i].sent) failed.add (list[i]);
            for (int i = outcomes.size; i < list.size; i++) failed.add (list[i]);
            if (failed.size > 0) {
                var fg = new PreferencesGroup (_("Not Sent"));
                foreach (var o in outcomes) if (!o.sent) fg.add_row (new ActionRow (o.to, o.error));
                box.append (fg);
            }
            string report = LettereMail.report (outcomes);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.halign = Align.END;
            bar.margin_top = 12;
            var save = new Button.with_label (_("Save Report…"));
            save.clicked.connect (() => {
                w.ask_save.begin (_("Save Sending Report"), _("Sending Report") + ".txt", { "txt" }, _("Text"), (obj, res) => {
                    var file = w.ask_save.end (res);
                    if (file == null) return;
                    try {
                        FileUtils.set_contents (file.get_path (), report);
                    } catch (Error e) {
                        w.show_error (_("Could Not Save the Report"), e.message);
                    }
                });
            });
            bar.append (save);
            if (failed.size > 0) {
                var retry = new Button.with_label (_("Retry Unsent"));
                retry.add_css_class ("suggested-action");
                retry.clicked.connect (() => {
                    dlg.close ();
                    mail_send.begin (w, failed);
                });
                bar.append (retry);
            }
            box.append (bar);
            dlg.open_dialog ();
        }
    }
}
