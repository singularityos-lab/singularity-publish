using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class PublishWindow : Singularity.Widgets.Window {
        public PublishApp app;
        public Document? doc { get; private set; }
        public PageCanvas canvas;
        public PagesPanel pages_panel;
        public Inspector inspector;
        public StylesPanel styles_panel;
        public SwatchesPanel swatches_panel;
        public LayersPanel layers_panel;
        public LinksPanel links_panel;
        public PreflightPanel preflight_panel;
        public SeparationsPanel separations_panel;
        public ReviewPanel review_panel;
        public LibraryPanel library_panel;
        public MergePanel merge_panel;
        private Stack content_stack;
        private Stack right_stack;
        private Revealer right_revealer;
        private ContextRibbon ribbon;
        private RibbonSelector style_selector;
        private RibbonSelector zoom_selector;
        private RibbonButton undo_item;
        private RibbonButton redo_item;
        private RibbonButton preflight_item;
        private RibbonToggle master_item;
        private Singularity.Widgets.InspectorPanel inspector_panel;
        private Box recent_list;
        private Box recent_wrap;
        private FlowBox template_flow;
        private Banner mode_banner;
        private Banner note_banner;
        public Banner macro_banner;
        private FindReplaceBar find_bar;
        private Singularity.Widgets.ToolPalette tools_box;
        private Gee.HashMap<Tool, ToggleButton> tool_buttons = new Gee.HashMap<Tool, ToggleButton> ();
        private Gee.ArrayList<Widget> doc_bubbles = new Gee.ArrayList<Widget> ();
        private bool close_confirmed = false;
        private bool syncing_tools = false;
        private uint thumb_timer = 0;
        private uint preflight_timer = 0;
        private uint autosave_id = 0;
        private string[] doc_actions = {};
        private int find_index = -1;
        private static Gee.ArrayList<Item> item_clip = new Gee.ArrayList<Item> ();
        private static Gee.HashMap<int, Story> item_clip_stories = new Gee.HashMap<int, Story> ();
        private static Gee.HashMap<string, Bytes> item_clip_media = new Gee.HashMap<string, Bytes> ();
        private static Story? text_clip = null;
        private static string text_clip_plain = "";
        private static int paste_offset = 0;

        public PublishWindow (PublishApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1400, 900);
            set_title (_("Publish"));
            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            content_stack.add_named (build_welcome (), "welcome");
            content_stack.add_named (build_editor (), "document");
            build_bubbles ();
            set_content (content_stack);
            install_actions ();
            close_request.connect (on_close_request);
            var drop = new DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var list = (Gdk.FileList) value.get_boxed ();
                foreach (var file in list.get_files ()) {
                    if (doc != null && is_image_name (file.get_basename ())) {
                        place_files ({ file });
                        continue;
                    }
                    app.open_file (file, this);
                    break;
                }
                return true;
            });
            ((Widget) this).add_controller (drop);
            show_welcome ();
        }

        public static bool is_image_name (string n) {
            string l = n.down ();
            foreach (string s in new string[] { ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".bmp", ".tif", ".tiff" }) if (l.has_suffix (s)) return true;
            return false;
        }

        public bool is_empty () {
            return doc == null || (!doc.modified && doc.path == null);
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.publish";
            wp.title = _("Publish");
            wp.subtitle = _("Lay out flyers, brochures, newsletters and cards for print");
            wp.add_action ("x-office-document", _("New Publication"), _("Choose the page size, margins, columns and bleed"), () => Dialogs.new_document (this));
            wp.add_action ("folder-open", _("Open"), _("Publish, Scribus, InDesign IDML and Publisher files"), () => app.choose_file (this));
            wp.add_action ("x-office-document-template", _("Browse Templates"), _("Flyers, brochures, cards, menus and more"), () => Dialogs.templates (this));
            var extra = new Box (Orientation.VERTICAL, 20);
            var tpl_title = new Label (_("Templates"));
            tpl_title.add_css_class ("title-2");
            tpl_title.halign = Align.START;
            extra.append (tpl_title);
            template_flow = new FlowBox ();
            template_flow.selection_mode = SelectionMode.NONE;
            template_flow.max_children_per_line = 4;
            template_flow.min_children_per_line = 2;
            template_flow.column_spacing = 10;
            template_flow.row_spacing = 10;
            template_flow.homogeneous = true;
            template_flow.halign = Align.START;
            int n = 0;
            foreach (var t in Templates.all ()) {
                if (n++ >= 8) break;
                var id = t.id;
                template_flow.append (Dialogs.template_card (t, 150, () => new_from_template (id)));
            }
            extra.append (template_flow);
            recent_wrap = new Box (Orientation.VERTICAL, 12);
            var recent_title = new Label (_("Recent"));
            recent_title.add_css_class ("title-2");
            recent_title.halign = Align.START;
            recent_list = new Box (Orientation.VERTICAL, 0);
            recent_wrap.append (recent_title);
            recent_wrap.append (recent_list);
            extra.append (recent_wrap);
            wp.set_extra_widget (extra);
            return wp;
        }

        private static bool is_publication (string uri) {
            string u = uri.down ();
            foreach (string s in PublishApp.open_suffixes ()) if (u.has_suffix ("." + s)) return true;
            return false;
        }

        private void fill_recent () {
            Widget? child;
            while ((child = recent_list.get_first_child ()) != null) recent_list.remove (child);
            var items = new Gee.ArrayList<RecentInfo> ();
            if (Singularity.Runtime.file_history_enabled ()) {
                foreach (var info in RecentManager.get_default ().get_items ()) {
                    if (is_publication (info.get_uri ()) && info.exists ()) items.add (info);
                }
            }
            items.sort ((a, b) => b.get_modified ().compare (a.get_modified ()));
            int count = 0;
            foreach (var info in items) {
                if (count++ >= 6) break;
                var file = File.new_for_uri (info.get_uri ());
                var row = new Button ();
                row.add_css_class ("flat");
                row.add_css_class ("publish-recent-row");
                var box = new Box (Orientation.HORIZONTAL, 12);
                var icon = new Image.from_icon_name ("x-office-document-symbolic");
                icon.pixel_size = 20;
                box.append (icon);
                var texts = new Box (Orientation.VERTICAL, 2);
                texts.hexpand = true;
                var name = new Label (file.get_basename ());
                name.halign = Align.START;
                name.ellipsize = Pango.EllipsizeMode.MIDDLE;
                name.add_css_class ("heading");
                var parent = file.get_parent ();
                string p = parent != null ? (parent.get_path () ?? parent.get_uri ()) : "";
                string home = Environment.get_home_dir ();
                if (p.has_prefix (home)) p = "~" + p.substring (home.length);
                var path = new Label (p);
                path.halign = Align.START;
                path.ellipsize = Pango.EllipsizeMode.START;
                path.add_css_class ("caption");
                path.add_css_class ("dim-label");
                texts.append (name);
                texts.append (path);
                box.append (texts);
                row.child = box;
                row.clicked.connect (() => app.open_file (file, this));
                recent_list.append (row);
            }
            recent_wrap.visible = count > 0;
        }

        private Widget build_editor () {
            var page = new Box (Orientation.HORIZONTAL, 0);
            var center = new Box (Orientation.VERTICAL, 0);
            center.hexpand = true;
            center.add_css_class ("publish-editor");
            apply_view_edge (center);
            ribbon = build_ribbon ();
            center.append (ribbon);
            mode_banner = new Banner (_("You are editing master pages. Changes appear on every page that uses them."), BannerStyle.INFO);
            mode_banner.button_label = _("Close Master Pages");
            mode_banner.button_clicked.connect (() => set_master_mode (false));
            mode_banner.visible = false;
            center.append (mode_banner);
            macro_banner = new Banner ("", BannerStyle.INFO);
            macro_banner.button_label = _("Run Macro");
            macro_banner.button_clicked.connect (() => {
                macro_banner.visible = false;
                MacrosUi.fire (this, "open");
            });
            macro_banner.visible = false;
            center.append (macro_banner);
            note_banner = new Banner ("", BannerStyle.WARNING);
            note_banner.button_label = _("Dismiss");
            note_banner.button_clicked.connect (() => note_banner.visible = false);
            note_banner.visible = false;
            center.append (note_banner);
            var overlay = new Overlay ();
            overlay.hexpand = true;
            overlay.vexpand = true;
            canvas = new PageCanvas ();
            canvas.selection_changed.connect (on_selection_changed);
            canvas.edited.connect (on_canvas_edited);
            canvas.text_changed.connect (on_text_changed);
            canvas.page_changed.connect (() => pages_panel.select_page (doc.current_page));
            canvas.context_requested.connect (show_canvas_menu);
            canvas.tool_changed.connect (sync_tools);
            canvas.zoom_changed.connect (sync_ribbon);
            canvas.item_double_clicked.connect ((it) => {
                if (canvas.selection.size == 0 || canvas.selection[0] != it) {
                    if (canvas.master_mode == false) {
                        var r = doc.pub.find_item (it.id);
                        if (r != null && r.master != null) {
                            override_master_item (it);
                            return;
                        }
                    }
                }
                toggle_panel ("format", true);
            });
            var scroll = new ScrolledWindow ();
            scroll.child = canvas;
            scroll.hexpand = true;
            scroll.vexpand = true;
            scroll.add_css_class ("publish-stage");
            scroll.hscrollbar_policy = PolicyType.EXTERNAL;
            overlay.child = scroll;
            tools_box = build_tools ();
            place_tools ();
            overlay.add_overlay (tools_box);
            find_bar = new FindReplaceBar ();
            find_bar.find_next.connect ((q) => find_step (q, 1));
            find_bar.find_prev.connect ((q) => find_step (q, -1));
            find_bar.replace_one.connect ((q, r) => replace_one (q, r));
            find_bar.replace_all.connect ((q, r) => replace_all (q, r));
            find_bar.closed.connect (() => canvas.grab_focus ());
            center.append (overlay);
            center.append (find_bar);
            page.append (center);
            inspector = new Inspector (this);
            styles_panel = new StylesPanel (this);
            swatches_panel = new SwatchesPanel (this);
            layers_panel = new LayersPanel (this);
            links_panel = new LinksPanel (this);
            preflight_panel = new PreflightPanel (this);
            separations_panel = new SeparationsPanel (this);
            review_panel = new ReviewPanel (this);
            library_panel = new LibraryPanel (this);
            canvas.page_pointer.connect ((pg, x, y) => separations_panel.show_ink (pg, x, y));
            merge_panel = new MergePanel (this);
            inspector_panel = new Singularity.Widgets.InspectorPanel (372, false);
            inspector_panel.compact_tabs = true;
            inspector_panel.add_page ("format", _("Format"), "document-properties-symbolic", inspector, true);
            inspector_panel.add_page ("styles", _("Styles"), "format-text-bold-symbolic", styles_panel, true);
            inspector_panel.add_page ("swatches", _("Swatches"), "applications-graphics-symbolic", swatches_panel, true);
            inspector_panel.add_page ("layers", _("Layers"), "view-dual-symbolic", layers_panel, true);
            inspector_panel.add_page ("links", _("Links"), "insert-link-symbolic", links_panel, false);
            inspector_panel.add_page ("preflight", _("Preflight"), "emblem-ok-symbolic", preflight_panel, false);
            inspector_panel.add_page ("separations", _("Separations"), "color-select-symbolic", separations_panel, false);
            inspector_panel.add_page ("review", _("Review"), "mail-send-symbolic", review_panel, false);
            inspector_panel.add_page ("library", _("Library"), "folder-symbolic", library_panel, false);
            inspector_panel.add_page ("merge", _("Mail Merge"), "x-office-spreadsheet-symbolic", merge_panel, false);
            inspector_panel.page_chosen.connect ((name) => toggle_panel (name, true));
            right_stack = inspector_panel.stack;
            right_revealer = new Revealer ();
            right_revealer.hexpand = false;
            right_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
            right_revealer.transition_duration = 200;
            right_revealer.child = inspector_panel;
            right_revealer.reveal_child = app.get_bool ("show-format-panel", true);
            page.append (right_revealer);
            pages_panel = new PagesPanel (this);
            set_sidebar (pages_panel);
            set_sidebar_width (208);
            return page;
        }

        private ContextRibbon build_ribbon () {
            var r = new ContextRibbon ();
            build_home (r.add_context ("home", _("Home"), "format-text-bold-symbolic"));
            build_insert (r.add_context ("insert", _("Insert"), "list-add-symbolic"));
            build_page_design (r.add_context ("design", _("Page Design"), "publish-pages-symbolic"));
            build_arrange (r.add_context ("arrange", _("Arrange"), "publish-bring-front-symbolic"));
            build_mailings (r.add_context ("mailings", _("Mailings"), "publish-merge-symbolic"));
            build_review (r.add_context ("review", _("Review"), "publish-preflight-symbolic"));
            build_view (r.add_context ("view", _("View"), "view-reveal-symbolic"));
            return r;
        }

        private RibbonButton labeled (RibbonContext c, string? icon, string label, string? tip, string action) {
            var b = c.add_button (icon, label, tip, action);
            b.label_in_compact = true;
            return b;
        }

        private void build_home (RibbonContext home) {
            undo_item = home.add_button ("edit-undo-symbolic", _("Undo"), null, "win.undo");
            redo_item = home.add_button ("edit-redo-symbolic", _("Redo"), null, "win.redo");
            home.add_separator ();
            home.add_button ("edit-cut-symbolic", _("Cut"), null, "win.cut");
            home.add_button ("edit-copy-symbolic", _("Copy"), null, "win.copy");
            home.add_button ("edit-paste-symbolic", _("Paste"), null, "win.paste");
            home.add_separator ();
            style_selector = home.add_selector (_("Paragraph Style"), 14);
            style_selector.text = _("Paragraph Style");
            style_selector.activated.connect (fill_style_selector);
            style_selector.changed.connect ((name) => {
                if (name == "") {
                    toggle_panel ("styles", true);
                    return;
                }
                format_paras (_("Paragraph Style"), (p) => p.style = name);
                sync_ribbon ();
            });
            home.add_button ("format-text-bold-symbolic", _("Bold"), null, "win.bold");
            home.add_button ("format-text-italic-symbolic", _("Italic"), null, "win.italic");
            home.add_button ("format-text-underline-symbolic", _("Underline"), null, "win.underline");
            home.add_button ("format-text-strikethrough-symbolic", _("Strikethrough"), null, "win.strike");
            home.add_button ("edit-clear-all-symbolic", _("Clear Overrides"), null, "win.clear-overrides");
            home.add_separator ();
            home.add_button ("format-justify-left-symbolic", _("Align Left"), null, "win.align-left");
            home.add_button ("format-justify-center-symbolic", _("Center"), null, "win.align-center");
            home.add_button ("format-justify-right-symbolic", _("Align Right"), null, "win.align-right");
            home.add_button ("format-justify-fill-symbolic", _("Justify"), null, "win.align-justify");
            home.add_separator ();
            home.add_button ("view-list-bullet-symbolic", _("Bulleted List"), null, "win.bullets");
            home.add_button ("view-list-ordered-symbolic", _("Numbered List"), null, "win.numbering");
            labeled (home, null, _("Drop Cap"), null, "win.drop-cap");
        }

        private void fill_style_selector () {
            style_selector.clear_options ();
            if (doc == null) return;
            foreach (var st in doc.pub.styles.paragraph) style_selector.add_option (st.name, st.name);
            style_selector.add_separator ();
            style_selector.add_extra ((m) => m.add_item (_("Styles Panel"), "format-text-bold-symbolic", () => toggle_panel ("styles", true)));
            var p = current_paragraph ();
            if (p != null) style_selector.selected = p.style;
        }

        private void build_insert (RibbonContext ins) {
            labeled (ins, "publish-text-frame-symbolic", _("Text Frame"), _("Insert a Text Frame"), "win.insert-text");
            labeled (ins, "image-x-generic-symbolic", _("Picture…"), _("Place a Picture"), "win.place");
            labeled (ins, "publish-table-symbolic", _("Table…"), _("Insert a Table"), "win.insert-table");
            var shape = ins.add_menu ("publish-rectangle-symbolic", _("Shape"), _("Insert a Shape"));
            shape.label_in_compact = true;
            shape.set_builder ((m) => {
                string[,] kinds = { { _("Rectangle"), "rect" }, { _("Ellipse"), "ellipse" }, { _("Polygon"), "polygon" }, { _("Star"), "star" }, { _("Line"), "line" } };
                for (int i = 0; i < kinds.length[0]; i++) {
                    string k = kinds[i, 1];
                    m.add_item (kinds[i, 0], null, () => activate_action_variant ("win.insert-shape", new Variant.string (k)));
                }
            });
            ins.add_button ("publish-image-frame-symbolic", _("Empty Image Frame"), null, "win.insert-image-frame");
            ins.add_separator ();
            labeled (ins, "document-new-symbolic", _("Page"), _("Add a Page"), "win.add-page");
            var field = ins.add_menu ("insert-object-symbolic", _("Field"), _("Insert a Text Field"));
            field.label_in_compact = true;
            field.set_builder ((m) => {
                m.add_item (_("Page Number"), null, () => run ("insert-page-number"));
                m.add_item (_("Page Count"), null, () => run ("insert-page-count"));
                m.add_item (_("Section Name"), null, () => run ("insert-section"));
                m.add_item (_("Next Page Number"), null, () => run ("insert-next-page"));
                m.add_item (_("Previous Page Number"), null, () => run ("insert-prev-page"));
                m.add_item (_("Date"), null, () => run ("insert-date"));
                m.add_item (_("Title"), null, () => run ("insert-title"));
            });
            ins.add_separator ();
            ins.add_button ("insert-link-symbolic", _("Hyperlink…"), null, "win.insert-hyperlink");
            ins.add_button ("accessories-character-map-symbolic", _("Symbol…"), null, "win.insert-symbol");
            ins.add_button ("font-x-generic-symbolic", _("WordArt…"), null, "win.insert-wordart");
            ins.add_button ("view-app-grid-symbolic", _("Building Blocks…"), null, "win.insert-building-block");
        }

        private void build_page_design (RibbonContext d) {
            labeled (d, "document-page-setup-symbolic", _("Setup…"), _("Document Setup"), "win.document-setup");
            master_item = d.add_toggle ("publish-master-symbolic", _("Master Pages"), _("Edit Master Pages"));
            master_item.label_in_compact = true;
            master_item.toggled.connect ((on) => {
                if (doc != null && on != canvas.master_mode) set_master_mode (on);
            });
            d.add_separator ();
            d.add_button ("document-new-symbolic", _("Add Page"), null, "win.add-page");
            d.add_button ("edit-copy-symbolic", _("Duplicate Page"), null, "win.duplicate-page");
            d.add_button ("user-trash-symbolic", _("Delete Page"), null, "win.delete-page");
            d.add_button ("view-paged-symbolic", _("Sections…"), null, "win.sections");
            d.add_separator ();
            d.add_button ("publish-guides-symbolic", _("Create Guides…"), null, "win.create-guides");
            d.add_separator ();
            d.add_button ("applications-graphics-symbolic", _("Color Schemes…"), null, "win.color-schemes");
            d.add_button ("preferences-desktop-font-symbolic", _("Font Schemes…"), null, "win.font-schemes");
        }

        private void build_arrange (RibbonContext arr) {
            arr.add_button ("publish-bring-front-symbolic", _("Bring to Front"), null, "win.bring-front");
            arr.add_button ("go-up-symbolic", _("Bring Forward"), null, "win.bring-forward");
            arr.add_button ("go-down-symbolic", _("Send Backward"), null, "win.send-backward");
            arr.add_button ("publish-send-back-symbolic", _("Send to Back"), null, "win.send-back");
            arr.add_separator ();
            arr.add_button ("publish-align-left-symbolic", _("Align Left Edges"), null, "win.arrange-left");
            arr.add_button ("publish-align-center-h-symbolic", _("Align Horizontal Centers"), null, "win.arrange-center");
            arr.add_button ("publish-align-right-symbolic", _("Align Right Edges"), null, "win.arrange-right");
            arr.add_button ("publish-align-top-symbolic", _("Align Top Edges"), null, "win.arrange-top");
            arr.add_button ("publish-align-center-v-symbolic", _("Align Vertical Centers"), null, "win.arrange-middle");
            arr.add_button ("publish-align-bottom-symbolic", _("Align Bottom Edges"), null, "win.arrange-bottom");
            arr.add_button ("publish-distribute-h-symbolic", _("Distribute Horizontally"), null, "win.distribute-h");
            arr.add_button ("publish-distribute-v-symbolic", _("Distribute Vertically"), null, "win.distribute-v");
            arr.add_separator ();
            arr.add_button ("publish-group-symbolic", _("Group"), null, "win.group");
            arr.add_button ("publish-ungroup-symbolic", _("Ungroup"), null, "win.ungroup");
            arr.add_button ("object-flip-horizontal-symbolic", _("Flip Horizontal"), null, "win.flip-h");
            arr.add_button ("object-flip-vertical-symbolic", _("Flip Vertical"), null, "win.flip-v");
            arr.add_button ("object-rotate-left-symbolic", _("Rotate 90° Counterclockwise"), null, "win.rotate-ccw");
            arr.add_button ("object-rotate-right-symbolic", _("Rotate 90° Clockwise"), null, "win.rotate-cw");
            arr.add_button ("changes-prevent-symbolic", _("Lock"), null, "win.lock");
        }

        private void build_mailings (RibbonContext m) {
            labeled (m, "publish-merge-symbolic", _("Mail Merge"), _("Show the Mail Merge panel"), "win.panel-merge");
            labeled (m, "system-users-symbolic", _("Recipients…"), _("Edit the Recipient List"), "win.merge-recipients");
            m.add_separator ();
            var preview = m.add_toggle ("view-reveal-symbolic", _("Preview Results"), null, "win.merge-preview");
            preview.label_in_compact = true;
            m.add_button ("go-first-symbolic", _("First Record"), null, "win.merge-first");
            m.add_button ("go-previous-symbolic", _("Previous Record"), null, "win.merge-prev");
            m.add_button ("go-next-symbolic", _("Next Record"), null, "win.merge-next");
            m.add_button ("go-last-symbolic", _("Last Record"), null, "win.merge-last");
            m.add_separator ();
            var finish = m.add_menu ("mail-send-symbolic", _("Finish and Merge"), _("Finish and Merge"));
            finish.label_in_compact = true;
            finish.set_builder ((menu) => {
                menu.add_item (_("Print…"), "document-print-symbolic", () => run ("merge-print"));
                menu.add_item (_("New Publication"), "document-new-symbolic", () => run ("merge-new"));
                menu.add_item (_("PDF…"), "x-office-document-symbolic", () => run ("merge-pdf"));
                menu.add_item (_("Email…"), "mail-send-symbolic", () => run ("merge-email"));
            });
        }

        private void build_review (RibbonContext r) {
            labeled (r, "tools-check-spelling-symbolic", _("Spelling…"), _("Check Spelling"), "win.spelling");
            r.add_button ("accessories-dictionary-symbolic", _("Thesaurus…"), null, "win.thesaurus");
            r.add_button ("edit-find-replace-symbolic", _("Find and Change…"), null, "win.find-advanced");
            r.add_button ("publish-story-editor-symbolic", _("Edit in Story Editor"), null, "win.story-editor");
            r.add_separator ();
            preflight_item = labeled (r, "emblem-ok-symbolic", _("Preflight"), null, "win.preflight");
            r.add_button ("emblem-documents-symbolic", _("Design Checker…"), null, "win.design-checker");
            r.add_button ("preferences-desktop-accessibility-symbolic", _("Accessibility Checker…"), null, "win.accessibility-checker");
            r.add_separator ();
            labeled (r, "mail-send-symbolic", _("Send for Review"), _("Export a proof PDF and open it in Reader"), "win.send-for-review");
        }

        private void build_view (RibbonContext view) {
            view.add_button ("zoom-out-symbolic", _("Zoom Out"), null, "win.zoom-out");
            zoom_selector = view.add_selector (_("Zoom"), 5);
            zoom_selector.text = "100%";
            foreach (int z in new int[] { 50, 75, 100, 150, 200, 400 }) zoom_selector.add_option (z.to_string (), "%d%%".printf (z));
            zoom_selector.add_separator ();
            zoom_selector.add_extra ((m) => {
                m.add_item (_("Fit Page"), "zoom-fit-best-symbolic", () => canvas.zoom_fit_page ());
                m.add_item (_("Fit Spread"), null, () => canvas.zoom_fit_spread ());
            });
            zoom_selector.changed.connect ((id) => canvas.zoom_to (int.parse (id) / 100.0 * 96.0 / 72.0));
            view.add_button ("zoom-in-symbolic", _("Zoom In"), null, "win.zoom-in");
            view.add_button ("zoom-fit-best-symbolic", _("Fit Page"), null, "win.zoom-fit");
            view.add_separator ();
            view.add_toggle (null, _("Rulers"), _("Show Rulers"), "win.show-rulers");
            view.add_toggle (null, _("Guides"), _("Show Guides"), "win.show-guides");
            view.add_toggle (null, _("Baseline Grid"), _("Show the Baseline Grid"), "win.show-baseline");
            view.add_toggle (null, _("Frame Edges"), _("Show Frame Edges"), "win.frame-edges");
            view.add_toggle (null, _("Hidden Characters"), _("Show Hidden Characters"), "win.hidden-chars");
            view.add_toggle (null, _("Preview"), _("Hide guides, frames and the pasteboard"), "win.preview-mode");
            view.add_separator ();
            view.add_toggle (null, _("Snap"), _("Snap to Guides"), "win.snap-guides");
            view.add_toggle (null, _("Smart Guides"), null, "win.smart-guides");
        }

        private void sync_ribbon () {
            if (doc == null || style_selector == null) return;
            var p = current_paragraph ();
            style_selector.text = p != null ? p.style : _("Paragraph Style");
            zoom_selector.text = "%d%%".printf ((int) Math.round (canvas.scale * 72.0 / 96.0 * 100));
        }

        private Singularity.Widgets.ToolPalette build_tools () {
            var box = new Singularity.Widgets.ToolPalette ();
            add_tool (box, Tool.SELECT, "publish-select-symbolic", "edit-select-symbolic", _("Selection (V)"));
            add_tool (box, Tool.CONTENT, "publish-content-symbolic", "view-fullscreen-symbolic", _("Content Grabber (A)"));
            add_tool (box, Tool.HAND, "publish-hand-symbolic", "input-mouse-symbolic", _("Hand (H)"));
            box.add_separator ();
            add_tool (box, Tool.TEXT, "publish-text-frame-symbolic", "insert-text-symbolic", _("Text Frame (T)"));
            add_tool (box, Tool.IMAGE_FRAME, "publish-image-frame-symbolic", "insert-image-symbolic", _("Image Frame (F)"));
            add_tool (box, Tool.TABLE, "publish-table-symbolic", "view-grid-symbolic", _("Table (B)"));
            box.add_separator ();
            add_tool (box, Tool.RECT, "publish-rectangle-symbolic", "checkbox-symbolic", _("Rectangle (M)"));
            add_tool (box, Tool.ELLIPSE, "publish-ellipse-symbolic", "radio-symbolic", _("Ellipse (L)"));
            add_tool (box, Tool.POLYGON, "publish-polygon-symbolic", "emblem-shared-symbolic", _("Polygon (P)"));
            add_tool (box, Tool.STAR, "publish-star-symbolic", "starred-symbolic", _("Star (S)"));
            add_tool (box, Tool.LINE, "publish-line-symbolic", "list-remove-symbolic", _("Line (\\)"));
            return box;
        }

        private void place_tools () {
            tools_box.inset (canvas.show_rulers ? CanvasRulers.SIZE : 0);
        }

        private void add_tool (Singularity.Widgets.ToolPalette box, Tool t, string icon, string fallback, string tip) {
            var theme = IconTheme.get_for_display (Gdk.Display.get_default ());
            var b = box.add_tool (theme.has_icon (icon) ? icon : fallback, tip);
            b.active = t == Tool.SELECT;
            b.toggled.connect (() => {
                if (syncing_tools) return;
                if (b.active) canvas.set_tool (t);
                else if (canvas.tool == t) {
                    syncing_tools = true;
                    b.active = true;
                    syncing_tools = false;
                }
            });
            tool_buttons[t] = b;
        }

        private void sync_tools () {
            syncing_tools = true;
            foreach (var e in tool_buttons.entries) e.value.active = e.key == canvas.tool;
            syncing_tools = false;
            if (canvas.thread_from != null) {
                var t = new Toast (_("Click a text frame or draw a new one to continue the story"));
                t.timeout = 3;
                add_toast (t);
            }
            sync_view_actions ();
        }

        private Widget track (Widget w) {
            doc_bubbles.add (w);
            return w;
        }

        private void anchor_to (Popover pop, Widget bubble) {
            if (pop.get_parent () == null) pop.set_parent (content_stack);
            Graphene.Rect bounds;
            if (bubble.compute_bounds (content_stack, out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                pop.pointing_to = rect;
            }
            pop.position = PositionType.BOTTOM;
        }

        public static void popup_menu (ContextMenu menu) {
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private ContextMenu bubble_menu (Widget bubble) {
            var menu = new ContextMenu (content_stack);
            anchor_to (menu, bubble);
            return menu;
        }

        private void build_bubbles () {
            track (add_bubble_icon ("go-previous-symbolic", _("Close Publication"), () => close_document ()));
            track (add_bubble_icon ("sidebar-show-symbolic", _("Pages (F9)"), () => run ("panel-pages")));
            ribbon.attach (this);
            track (ribbon.tabs);
            var find = add_bubble_icon ("edit-find-symbolic", _("Find and Replace (Ctrl+F)"), () => run ("find"));
            track (find);
            var format = add_bubble_icon ("document-properties-symbolic", _("Show Inspector (Ctrl+F9)"), () => toggle_panel (right_stack.visible_child_name ?? "format"));
            track (format);
            var export = add_bubble_suggested (_("Export"), () => { });
            export.tooltip_text = _("Export as PDF, images, web page, XPS, Word, ODG, IDML or Scribus");
            export.clicked.connect (() => {
                var menu = bubble_menu (export);
                menu.add_item (_("PDF for Print…"), "x-office-document-symbolic", () => run ("export-pdf"));
                menu.add_item (_("Images…"), "image-x-generic-symbolic", () => run ("export-images"));
                menu.add_item (_("Web Page (HTML)…"), "text-html-symbolic", () => run ("export-html"));
                menu.add_item (_("Web Site…"), null, () => run ("export-site"));
                menu.add_item (_("EPUB, Reflowable…"), null, () => run ("export-epub"));
                menu.add_item (_("EPUB, Fixed Layout…"), null, () => run ("export-epub-fixed"));
                menu.add_item (_("XPS Document…"), null, () => run ("export-xps"));
                menu.add_item (_("Word Document (DOCX)…"), null, () => run ("export-docx"));
                menu.add_item (_("OpenDocument Drawing (ODG)…"), null, () => run ("export-odg"));
                menu.add_item (_("InDesign Markup (IDML)…"), null, () => run ("export-idml"));
                menu.add_item (_("Scribus Document…"), null, () => run ("export-sla"));
                menu.add_separator ();
                menu.add_item (_("Print…"), "document-print-symbolic", () => run ("print"));
                menu.add_item (_("Package for a Printer…"), "folder-symbolic", () => run ("package"));
                var share = lookup_action ("share");
                if (share != null && share.enabled) menu.add_item (_("Share…"), "singularity-share-symbolic", () => run ("share"));
                menu.add_item (_("Send as Email…"), "mail-send-symbolic", () => run ("send-email"));
                popup_menu (menu);
            });
            track (export);
            set_bubble_priority (export, BUBBLE_PRIORITY_PINNED);
        }

        public void toggle_panel (string name, bool force = false) {
            if (doc == null) return;
            if (!force && right_revealer.reveal_child && right_stack.visible_child_name == name) {
                right_revealer.reveal_child = false;
            } else {
                inspector_panel.page = name;
                right_revealer.reveal_child = true;
                refresh_panel (name);
            }
            app.set_bool ("show-format-panel", right_revealer.reveal_child);
        }

        private void refresh_panel (string name) {
            switch (name) {
                case "format": inspector.rebuild (); break;
                case "styles": styles_panel.rebuild (); break;
                case "swatches": swatches_panel.rebuild (); break;
                case "layers": layers_panel.rebuild (); break;
                case "links": links_panel.rebuild (); break;
                case "preflight": preflight_panel.rebuild (); break;
                case "separations": separations_panel.rebuild (); break;
                case "review": review_panel.rebuild (); break;
                case "library": library_panel.rebuild (); break;
                case "merge": merge_panel.rebuild (); break;
            }
        }

        public void refresh_visible_panel () {
            if (!right_revealer.reveal_child) return;
            refresh_panel (right_stack.visible_child_name);
        }

        private void show_welcome () {
            content_stack.visible_child_name = "welcome";
            foreach (var w in doc_bubbles) w.visible = false;
            set_sidebar_visible (false);
            fill_recent ();
            set_title (_("Publish"));
            sync_actions ();
        }

        public void new_from_template (string id) {
            var p = Templates.build (id);
            var d = new Document (p);
            if (doc != null && !is_empty ()) {
                var nw = new PublishWindow (app);
                nw.present ();
                nw.load_document (d);
                return;
            }
            load_document (d);
        }

        public void new_blank (DocSettings s, int pages) {
            var d = new Document (Templates.blank (s, pages));
            if (doc != null && !is_empty ()) {
                var nw = new PublishWindow (app);
                nw.present ();
                nw.load_document (d);
                return;
            }
            load_document (d);
        }

        public void load_document (Document d) {
            if (doc != null) {
                doc.changed.disconnect (on_doc_changed);
                doc.replaced.disconnect (on_doc_replaced);
            }
            doc = d;
            doc.changed.connect (on_doc_changed);
            doc.replaced.connect (on_doc_replaced);
            content_stack.visible_child_name = "document";
            foreach (var w in doc_bubbles) w.visible = true;
            canvas.set_document (doc);
            apply_view_settings ();
            mode_banner.visible = false;
            if (doc.import_note != "") {
                note_banner.title = doc.import_note.split ("\n")[0];
                note_banner.tooltip_text = doc.import_note;
                note_banner.visible = true;
            } else {
                note_banner.visible = false;
            }
            pages_panel.load ();
            set_sidebar_visible (true);
            update_title ();
            sync_actions ();
            setup_autosave ();
            refresh_visible_panel ();
            schedule_preflight ();
            canvas.grab_focus ();
            MacrosUi.document_opened (this);
        }

        private void apply_view_settings () {
            canvas.show_rulers = app.get_bool ("show-rulers", true);
            place_tools ();
            canvas.show_guides = app.get_bool ("show-guides", true);
            canvas.snap = app.get_bool ("snap-to-guides", true);
            canvas.smart = app.get_bool ("smart-guides", true);
            canvas.show_baseline = app.get_bool ("show-baseline-grid", false);
            canvas.frame_edges = app.get_bool ("show-frame-edges", true);
            sync_view_actions ();
        }

        private void setup_autosave () {
            if (autosave_id != 0) Source.remove (autosave_id);
            autosave_id = 0;
            int interval = app.get_int ("autosave-interval", 0);
            if (interval <= 0) return;
            autosave_id = Timeout.add_seconds (interval, () => {
                if (doc != null && doc.modified && doc.path != null && canvas.edit == null) {
                    try {
                        doc.save_to (doc.path);
                        CloudActions.sync_back (this, File.new_for_path (doc.path));
                    } catch (Error e) {
                        warning ("autosave: %s", e.message);
                    }
                }
                return Source.CONTINUE;
            });
        }

        private void on_doc_changed () {
            update_title ();
        }

        private void on_doc_replaced () {
            int[] ids = canvas.selected_ids ();
            canvas.end_edit ();
            canvas.rebind ();
            canvas.reselect_ids (ids);
            pages_panel.load ();
            refresh_visible_panel ();
            schedule_preflight ();
        }

        public void update_title () {
            if (doc == null) return;
            string name;
            if (doc.path != null) name = Path.get_basename (doc.path);
            else if (doc.pub.meta.title != "") name = doc.pub.meta.title;
            else name = _("Untitled Publication");
            set_title ((doc.modified ? "* " : "") + name);
            undo_item.widget.sensitive = doc.can_undo;
            redo_item.widget.sensitive = doc.can_redo;
            undo_item.tooltip = doc.can_undo ? _("Undo %s").printf (doc.undo_label) : null;
            redo_item.tooltip = doc.can_redo ? _("Redo %s").printf (doc.redo_label) : null;
            sync_share ();
        }

        private void on_selection_changed () {
            sync_ribbon ();
            if (right_revealer.reveal_child && right_stack.visible_child_name == "format") inspector.rebuild ();
            else if (right_revealer.reveal_child && right_stack.visible_child_name == "styles") styles_panel.sync_current ();
            else if (right_revealer.reveal_child && right_stack.visible_child_name == "layers") layers_panel.rebuild ();
            sync_actions ();
        }

        private void on_canvas_edited () {
            inspector.sync_geometry ();
            schedule_thumbnail ();
            schedule_preflight ();
            update_title ();
        }

        private void on_text_changed () {
            sync_ribbon ();
            schedule_thumbnail ();
            schedule_preflight ();
            update_title ();
            if (right_revealer.reveal_child && right_stack.visible_child_name == "format") inspector.sync_text ();
        }

        public void content_edited () {
            canvas.invalidate ();
            schedule_thumbnail ();
            schedule_preflight ();
            update_title ();
        }

        private void schedule_thumbnail () {
            if (thumb_timer != 0) Source.remove (thumb_timer);
            thumb_timer = Timeout.add (250, () => {
                thumb_timer = 0;
                pages_panel.refresh_current ();
                return Source.REMOVE;
            });
        }

        public void schedule_preflight () {
            if (preflight_timer != 0) Source.remove (preflight_timer);
            preflight_timer = Timeout.add (900, () => {
                preflight_timer = 0;
                update_preflight_badge ();
                return Source.REMOVE;
            });
        }

        private void update_preflight_badge () {
            if (doc == null) return;
            var pf = PreflightPanel.prepare (this);
            pf.run ();
            int errors = pf.count (Severity.ERROR), warns = pf.count (Severity.WARNING);
            preflight_item.icon_name = errors > 0 ? "dialog-error-symbolic" : (warns > 0 ? "dialog-warning-symbolic" : "emblem-ok-symbolic");
            string prof = PreflightProfile.display_name (pf.profile.name);
            if (errors > 0) preflight_item.tooltip = ngettext ("Preflight (%s): %d error", "Preflight (%s): %d errors", errors).printf (prof, errors);
            else if (warns > 0) preflight_item.tooltip = ngettext ("Preflight (%s): %d warning", "Preflight (%s): %d warnings", warns).printf (prof, warns);
            else preflight_item.tooltip = _("Preflight (%s): no problems").printf (prof);
            if (right_revealer.reveal_child && right_stack.visible_child_name == "preflight") preflight_panel.rebuild ();
        }

        public void set_master_mode (bool on, string? master = null) {
            if (doc == null) return;
            canvas.end_edit ();
            canvas.master_mode = on;
            if (master != null) canvas.master_id = master;
            else if (on) {
                var pg = doc.page;
                canvas.master_id = pg != null && pg.master != "" ? pg.master : (doc.pub.masters.size > 0 ? doc.pub.masters[0].id : "A");
            }
            canvas.selection.clear ();
            canvas.sel_left = false;
            canvas.relayout ();
            canvas.queue_allocate ();
            canvas.fit_spread = on && doc.pub.settings.facing;
            canvas.auto_fit = true;
            if (canvas.fit_spread) canvas.zoom_fit_spread ();
            else canvas.zoom_fit_page ();
            canvas.auto_fit = true;
            mode_banner.visible = on;
            master_item.active = on;
            pages_panel.show_masters (on);
            refresh_visible_panel ();
            canvas.queue_draw ();
        }

        public void go_to_page (int index) {
            if (doc == null) return;
            if (canvas.master_mode) set_master_mode (false);
            index = index.clamp (0, doc.pub.pages.size - 1);
            canvas.end_edit ();
            doc.current_page = index;
            canvas.sel_page = index;
            canvas.select_only (null);
            canvas.show_page (index);
            pages_panel.select_page (index);
            refresh_visible_panel ();
        }

        public void close_document () {
            if (doc == null) {
                show_welcome ();
                return;
            }
            confirm_discard (() => {
                canvas.end_edit ();
                canvas.set_document (null);
                doc = null;
                if (autosave_id != 0) Source.remove (autosave_id);
                autosave_id = 0;
                show_welcome ();
            });
        }

        public delegate void Then ();

        private void confirm_discard (owned Then then) {
            if (doc == null || !doc.modified) {
                then ();
                return;
            }
            var dlg = new ConfirmDialog (app, _("Save Changes?"), "dialog-warning",
                _("Your changes will be lost if you do not save them."),
                _("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.set_secondary (_("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.CANCEL) return;
                if (r == ConfirmDialog.Response.SECONDARY) {
                    save.begin (false, (obj, res) => {
                        if (save.end (res)) then ();
                    });
                    return;
                }
                then ();
            });
            dlg.present ();
        }

        private bool on_close_request () {
            if (close_confirmed || doc == null || !doc.modified) return false;
            confirm_discard (() => {
                close_confirmed = true;
                close ();
            });
            return true;
        }

        public static FileFilter filter (string name, string[] suffixes) {
            var f = new FileFilter ();
            f.name = name;
            foreach (string s in suffixes) f.add_suffix (s);
            return f;
        }

        public string base_name (string fallback) {
            string n;
            if (doc.path != null) n = Path.get_basename (doc.path);
            else if (doc.pub.meta.title != "") n = doc.pub.meta.title;
            else n = fallback;
            int dot = n.last_index_of (".");
            if (dot > 0) n = n.substring (0, dot);
            return n;
        }

        public File default_folder () {
            if (doc != null && doc.path != null) return File.new_for_path (Path.get_dirname (doc.path));
            string? docs = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);
            return File.new_for_path (docs != null && FileUtils.test (docs, FileTest.IS_DIR) ? docs : Environment.get_home_dir ());
        }

        public async bool save (bool save_as) {
            if (doc == null) return false;
            string? target = save_as ? null : doc.path;
            if (target != null && !FileKind.from_path (target).can_save ()) target = null;
            if (target == null) {
                var dialog = new FileDialog ();
                dialog.title = _("Save Publication");
                dialog.initial_name = base_name (_("Publication")) + "." + NativeFormat.EXT;
                dialog.initial_folder = default_folder ();
                var filters = new GLib.ListStore (typeof (FileFilter));
                filters.append (filter (_("Publish Document"), { NativeFormat.EXT }));
                filters.append (filter (_("Scribus Document"), { "sla" }));
                dialog.filters = filters;
                try {
                    var file = yield dialog.save (this, null);
                    if (file == null) return false;
                    target = file.get_path ();
                    var k = FileKind.from_path (target);
                    if (!k.can_save ()) target += "." + NativeFormat.EXT;
                } catch (Error e) {
                    return false;
                }
            }
            try {
                doc.save_to (target);
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (File.new_for_path (target).get_uri ());
                update_title ();
                var toast = new Toast (_("Saved \"%s\"").printf (Path.get_basename (target)));
                toast.timeout = 2;
                add_toast (toast);
                CloudActions.sync_back (this, File.new_for_path (target));
                return true;
            } catch (Error e) {
                show_error (_("Could Not Save"), e.message);
                return false;
            }
        }

        public async File? ask_save (string title, string name, string[] suffixes, string filter_name) {
            var dialog = new FileDialog ();
            dialog.initial_folder = default_folder ();
            dialog.title = title;
            dialog.initial_name = name;
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter (filter_name, suffixes));
            dialog.filters = filters;
            try {
                return yield dialog.save (this, null);
            } catch (Error e) {
                return null;
            }
        }

        public async void export_pdf_to (Publication p, ExportOptions opts, string name) {
            var file = yield ask_save (_("Export PDF"), name + ".pdf", { "pdf" }, _("PDF Document"));
            if (file == null) return;
            try {
                var ex = new Exporter (p, opts);
                int n = ex.export_pdf (file.get_path ());
                var report = PdfxReport.verify (file.get_path (), opts.color_mode);
                if (report.version != "" && !report.passed) {
                    show_error (_("The PDF Does Not Meet %s").printf (report.version), string.joinv ("\n", report.problems.to_array ()));
                    return;
                }
                string msg = report.version != "" ? ngettext ("Exported %d page to \"%s\", checked as %s", "Exported %d pages to \"%s\", checked as %s", n).printf (n, file.get_basename (), report.version) : ngettext ("Exported %d page to \"%s\"", "Exported %d pages to \"%s\"", n).printf (n, file.get_basename ());
                var t = new Toast (msg);
                add_toast (t);
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
            }
        }

        public async void export_images_to (ExportOptions opts, string format) {
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Folder for the Images");
            dialog.initial_folder = default_folder ();
            try {
                var folder = yield dialog.select_folder (this, null);
                if (folder == null) return;
                var ex = new Exporter (doc.pub, opts);
                var files = ex.export_images (folder.get_path (), base_name (_("Page")), format);
                add_toast (new Toast (ngettext ("Exported %d image", "Exported %d images", files.size).printf (files.size)));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Export"), e.message);
            }
        }

        private async void export_sla () {
            if (doc == null) return;
            var file = yield ask_save (_("Export Scribus Document"), base_name (_("Publication")) + ".sla", { "sla" }, _("Scribus Document"));
            if (file == null) return;
            try {
                var w = new SlaWriter (doc.pub);
                FileUtils.set_contents (file.get_path (), w.write ());
                add_toast (new Toast (_("Exported \"%s\"").printf (file.get_basename ())));
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
            }
        }

        public void print_publication (Publication p, ExportOptions? opts = null) {
            if (p.pages.size == 0) return;
            int current = doc != null && p == doc.pub ? doc.current_page : 0;
            var source = new PublishPrintSource (p, base_name (_("Publication")), current, opts);
            var initial = Singularity.Print.PresetStore.get_default ().last_used (app.application_id ?? "dev.sinty.publish") ?? new Singularity.Print.JobOptions ();
            initial.landscape = p.settings.width > p.settings.height && (opts == null || opts.impose == ImposeMode.NONE);
            Singularity.Print.run_source.begin (this, source, initial);
        }

        public void show_error (string title, string message) {
            var dlg = new ConfirmDialog.message (app, title, "dialog-error", message);
            dlg.transient_for = this;
            dlg.present ();
        }

        public void toast (string text) {
            add_toast (new Toast (text));
        }

        private void sync_actions () {
            foreach (string name in doc_actions) {
                var a = lookup_action (name) as SimpleAction;
                if (a != null) a.set_enabled (doc != null);
            }
            sync_share ();
        }

        private void sync_share () {
            var a = lookup_action ("share") as SimpleAction;
            bool can = doc != null && doc.path != null;
            if (a != null) a.set_enabled (can);
        }

        public void run (string name) {
            activate_action (name, null);
        }

        private delegate void Act ();

        public delegate void DocAct ();

        public void doc_action (string name, owned DocAct handler) {
            var a = new SimpleAction (name, null);
            doc_actions += name;
            a.activate.connect (() => {
                if (doc == null) return;
                if (recording != null && !name.has_prefix ("macro-")) recording.append ("action %s\n".printf (name));
                MacrosUi.before_action (this, name);
                handler ();
                MacrosUi.after_action (this, name);
            });
            add_action (a);
        }

        public delegate void DocParamAct (string param);

        public void doc_param_action (string name, owned DocParamAct handler) {
            var a = new SimpleAction (name, VariantType.STRING);
            doc_actions += name;
            a.activate.connect ((v) => {
                if (doc == null) return;
                if (recording != null) recording.append ("action %s \"%s\"\n".printf (name, v.get_string ().replace ("\"", "\\\"")));
                handler (v.get_string ());
            });
            add_action (a);
        }

        public StringBuilder? recording = null;

        private static string? text_action (string name) {
            switch (name) {
                case "copy": return "clipboard.copy";
                case "cut": return "clipboard.cut";
                case "paste": return "clipboard.paste";
                case "select-all": return "selection.select-all";
                case "undo": return "text.undo";
                case "redo": return "text.redo";
                default: return null;
            }
        }

        private bool focus_in_text () {
            var f = get_focus ();
            return f != null && (f is Gtk.Text || f is Gtk.TextView) && f != canvas;
        }

        private void act (string name, owned Act handler, bool needs_doc = true) {
            var a = new SimpleAction (name, null);
            if (needs_doc) doc_actions += name;
            string? forward = text_action (name);
            a.activate.connect (() => {
                if (forward != null && focus_in_text ()) {
                    get_focus ().activate_action_variant (forward, null);
                    return;
                }
                if (needs_doc && doc == null) return;
                if (recording != null && needs_doc) recording.append ("action %s\n".printf (name));
                if (needs_doc) MacrosUi.before_action (this, name);
                handler ();
                if (needs_doc) MacrosUi.after_action (this, name);
            });
            add_action (a);
        }

        private delegate void BoolAct (bool v);

        private void toggle_act (string name, bool initial, owned BoolAct handler) {
            var a = new SimpleAction.stateful (name, null, new Variant.boolean (initial));
            doc_actions += name;
            a.activate.connect (() => {
                if (doc == null) return;
                bool v = !a.get_state ().get_boolean ();
                a.set_state (new Variant.boolean (v));
                handler (v);
            });
            add_action (a);
        }

        private void set_toggle_state (string name, bool v) {
            var a = lookup_action (name) as SimpleAction;
            if (a != null) a.set_state (new Variant.boolean (v));
        }

        private void sync_view_actions () {
            set_toggle_state ("show-rulers", canvas.show_rulers);
            set_toggle_state ("show-guides", canvas.show_guides);
            set_toggle_state ("snap-guides", canvas.snap);
            set_toggle_state ("smart-guides", canvas.smart);
            set_toggle_state ("show-baseline", canvas.show_baseline);
            set_toggle_state ("frame-edges", canvas.frame_edges);
            set_toggle_state ("preview-mode", canvas.preview);
            set_toggle_state ("hidden-chars", canvas.hidden_chars);
            if (doc != null) set_toggle_state ("merge-preview", doc.pub.merge.preview >= 0);
            if (doc != null) set_toggle_state ("merge-catalogue", doc.pub.merge.catalogue);
            tools_box.visible = !canvas.preview;
        }

        public Gee.List<Item> sel () {
            return canvas.selection;
        }

        public void edit (string label, owned Document.EditFunc f, string key = "") {
            if (doc == null) return;
            doc.checkpoint (label, key);
            f ();
            doc.touch ();
            content_edited ();
            inspector.sync_geometry ();
        }

        public void text_story_edit (string label) {
            canvas.text_edited ();
        }

        public delegate void RunEdit (Run r);
        public delegate void ParaEdit (Paragraph p);

        public Gee.ArrayList<Story> target_stories () {
            var list = new Gee.ArrayList<Story> ();
            foreach (var it in sel ()) collect_stories (it, list);
            return list;
        }

        private void collect_stories (Item it, Gee.ArrayList<Story> list) {
            var t = it as TextFrame;
            if (t != null) {
                var s = doc.pub.story (t.story);
                if (!list.contains (s)) list.add (s);
                return;
            }
            var tb = it as TableItem;
            if (tb != null) {
                bool range = canvas.cell_r1 >= 0 && sel ().size == 1;
                int r1 = range ? int.min (canvas.cell_r1, canvas.cell_r2) : 0, r2 = range ? int.max (canvas.cell_r1, canvas.cell_r2) : tb.rows - 1;
                int c1 = range ? int.min (canvas.cell_c1, canvas.cell_c2) : 0, c2 = range ? int.max (canvas.cell_c1, canvas.cell_c2) : tb.cols - 1;
                for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) list.add (tb.cells[r][c].story);
                return;
            }
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) collect_stories (c, list);
        }

        public void format_runs (string label, owned RunEdit f, string key = "") {
            var e = canvas.edit;
            if (e != null) {
                if (!e.has_selection ()) {
                    var tmpl = (e.pending ?? e.story.format_at (e.caret)).clone ();
                    f (tmpl);
                    e.pending = tmpl;
                    canvas.queue_draw ();
                    inspector.sync_text ();
                    return;
                }
                TextPos a, b;
                e.ordered (out a, out b);
                doc.checkpoint (label, key);
                e.story.apply_chars (a, b, (r) => f (r));
                doc.touch ();
                canvas.text_edited ();
                inspector.sync_text ();
                return;
            }
            var stories = target_stories ();
            if (stories.size == 0) return;
            edit (label, () => {
                foreach (var s in stories) s.apply_chars (TextPos (0, 0), s.end_pos (), (r) => f (r));
            }, key);
            inspector.sync_text ();
        }

        public void format_paras (string label, owned ParaEdit f, string key = "") {
            var e = canvas.edit;
            if (e != null) {
                doc.checkpoint (label, key);
                e.story.apply_paras (e.anchor, e.caret, (p) => f (p));
                doc.touch ();
                canvas.text_edited ();
                inspector.sync_text ();
                return;
            }
            var stories = target_stories ();
            if (stories.size == 0) return;
            edit (label, () => {
                foreach (var s in stories) s.apply_paras (TextPos (0, 0), s.end_pos (), (p) => f (p));
            }, key);
            inspector.sync_text ();
        }

        public CharFormat current_chars () {
            var cf = CharFormat.defaults ();
            var e = canvas.edit;
            Story? s = null;
            TextPos pos = TextPos (0, 0);
            if (e != null) {
                s = e.story;
                TextPos a, b;
                e.ordered (out a, out b);
                pos = e.has_selection () ? TextPos (a.para, a.offset + 1) : e.caret;
            } else {
                var st = target_stories ();
                if (st.size > 0) s = st[0];
                pos = TextPos (0, 1);
            }
            if (s == null) return cf;
            pos = s.clamp (pos);
            var p = s.paras[pos.para];
            var pf = new ParaFormat ();
            doc.pub.styles.resolve_paragraph (p.style, pf, cf);
            var r = e != null && e.pending != null && !e.has_selection () ? e.pending : s.format_at (pos);
            return ParaBuild.resolve_run (doc.pub, cf, r);
        }

        public Paragraph? current_paragraph () {
            var e = canvas.edit;
            if (e != null) return e.story.paras[e.caret.para.clamp (0, e.story.paras.size - 1)];
            var st = target_stories ();
            if (st.size > 0 && st[0].paras.size > 0) return st[0].paras[0];
            return null;
        }

        public ParaFormat current_para_format () {
            var pf = ParaFormat.defaults ();
            var p = current_paragraph ();
            if (p == null) return pf;
            var cf = new CharFormat ();
            doc.pub.styles.resolve_paragraph (p.style, pf, cf);
            pf.apply (p.fmt);
            return pf;
        }

        private void font_step (bool bigger) {
            double cur = current_chars ().size;
            double[] steps = { 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 60, 72, 96, 120, 144, 200, 300 };
            double target = cur;
            if (bigger) {
                foreach (double s in steps) if (s > cur + 0.1) {
                    target = s;
                    break;
                }
            } else {
                for (int i = steps.length - 1; i >= 0; i--) if (steps[i] < cur - 0.1) {
                    target = steps[i];
                    break;
                }
            }
            format_runs (_("Font Size"), (r) => r.fmt.size = target);
        }

        private void install_actions () {
            act ("save", () => save.begin (false));
            act ("save-as", () => save.begin (true));
            act ("save-online", () => CloudActions.save_document (this));
            act ("place", () => place.begin ());
            act ("export-pdf", () => Dialogs.export_pdf (this));
            act ("export-images", () => Dialogs.export_images (this));
            act ("export-sla", () => export_sla.begin ());
            act ("print", () => print_publication (doc.pub));
            act ("package", () => package.begin ());
            var share = Singularity.Share.add_action (this, this, () => {
                return doc != null && doc.path != null ? new Singularity.ShareContent.for_files ({ File.new_for_path (doc.path) }) : null;
            });
            share.set_enabled (false);
            act ("document-setup", () => Dialogs.document_setup (this));
            act ("properties", () => Dialogs.properties (this));
            act ("close-doc", () => close_document ());
            act ("close", () => close (), false);
            act ("undo", () => {
                canvas.end_edit ();
                doc.undo ();
            });
            act ("redo", () => {
                canvas.end_edit ();
                doc.redo ();
            });
            act ("cut", () => {
                if (canvas.edit != null) {
                    copy_text ();
                    canvas.delete_selected_text ();
                    return;
                }
                copy_items ();
                delete_items (_("Cut"));
            });
            act ("copy", () => {
                if (canvas.edit != null) copy_text ();
                else copy_items ();
            });
            act ("paste", () => paste.begin (false));
            act ("paste-in-place", () => paste.begin (true));
            act ("duplicate", () => duplicate_items (12, 12, 1));
            act ("step-repeat", () => Dialogs.step_repeat (this));
            act ("delete", () => {
                if (canvas.edit != null) {
                    canvas.delete_selected_text ();
                    return;
                }
                delete_items (_("Delete"));
            });
            act ("select-all", () => canvas.select_all ());
            act ("deselect", () => canvas.clear_selection ());
            act ("find", () => {
                find_index = -1;
                find_bar.open_replace ();
                string sel_text = canvas.selected_text ();
                if (sel_text != "" && !sel_text.contains ("\n")) find_bar.find_text = sel_text;
            });
            act ("spelling", () => Dialogs.spelling (this));
            act ("story-editor", () => {
                var s = current_story ();
                if (s != null) new StoryEditor (this, s).present ();
                else toast (_("Select a text frame to edit its story"));
            });
            act ("preflight", () => toggle_panel ("preflight", true));
            act ("zoom-in", () => canvas.zoom_to (canvas.scale * 1.25));
            act ("zoom-out", () => canvas.zoom_to (canvas.scale / 1.25));
            act ("zoom-fit", () => canvas.zoom_fit_page ());
            act ("zoom-spread", () => canvas.zoom_fit_spread ());
            act ("zoom-actual", () => canvas.zoom_to (96.0 / 72.0));
            toggle_act ("show-rulers", true, (v) => {
                canvas.show_rulers = v;
                place_tools ();
                app.set_bool ("show-rulers", v);
                canvas.queue_draw ();
            });
            toggle_act ("show-guides", true, (v) => {
                canvas.show_guides = v;
                app.set_bool ("show-guides", v);
                canvas.queue_draw ();
            });
            toggle_act ("snap-guides", true, (v) => {
                canvas.snap = v;
                app.set_bool ("snap-to-guides", v);
            });
            toggle_act ("smart-guides", true, (v) => {
                canvas.smart = v;
                app.set_bool ("smart-guides", v);
            });
            toggle_act ("show-baseline", false, (v) => {
                canvas.show_baseline = v;
                app.set_bool ("show-baseline-grid", v);
                canvas.queue_draw ();
            });
            toggle_act ("frame-edges", true, (v) => {
                canvas.frame_edges = v;
                app.set_bool ("show-frame-edges", v);
                canvas.queue_draw ();
            });
            toggle_act ("preview-mode", false, (v) => {
                canvas.preview = v;
                tools_box.visible = !v;
                canvas.queue_draw ();
            });
            toggle_act ("hidden-chars", false, (v) => {
                canvas.hidden_chars = v;
                canvas.queue_draw ();
            });
            act ("panel-pages", () => set_sidebar_visible (!get_sidebar_visible ()));
            act ("panel-format", () => toggle_panel ("format"));
            act ("panel-styles", () => toggle_panel ("styles"));
            act ("panel-swatches", () => toggle_panel ("swatches"));
            act ("panel-layers", () => toggle_panel ("layers"));
            act ("panel-links", () => toggle_panel ("links"));
            act ("panel-preflight", () => toggle_panel ("preflight"));
            act ("panel-separations", () => toggle_panel ("separations", true));
            act ("panel-review", () => toggle_panel ("review", true));
            act ("panel-library", () => toggle_panel ("library", true));
            act ("toggle-separations", () => {
                canvas.separations = !canvas.separations;
                if (canvas.separations && canvas.sep_enabled.size == 0) canvas.sep_enabled.add_all (PrepressExport.plates (doc.pub));
                canvas.drop_separations ();
                canvas.queue_draw ();
                toggle_panel ("separations", true);
            });
            act ("panel-merge", () => toggle_panel ("merge"));
            act ("insert-text", () => insert_frame (Tool.TEXT));
            act ("insert-image-frame", () => insert_frame (Tool.IMAGE_FRAME));
            act ("insert-table", () => Dialogs.insert_table (this));
            var shape = new SimpleAction ("insert-shape", VariantType.STRING);
            shape.activate.connect ((v) => {
                if (doc == null) return;
                insert_shape (ShapeKind.parse (v.get_string ()));
            });
            add_action (shape);
            doc_actions += "insert-shape";
            act ("insert-page-number", () => insert_field_or_frame (Fields.PAGE));
            act ("insert-page-count", () => insert_field_or_frame (Fields.PAGES));
            act ("insert-section", () => insert_field_or_frame (Fields.SECTION));
            act ("insert-next-page", () => insert_field_or_frame (Fields.NEXT_PAGE));
            act ("insert-prev-page", () => insert_field_or_frame (Fields.PREV_PAGE));
            act ("insert-date", () => insert_field_or_frame (Fields.DATE));
            act ("insert-title", () => insert_field_or_frame (Fields.TITLE));
            var ch = new SimpleAction ("insert-char", VariantType.STRING);
            ch.activate.connect ((v) => {
                if (canvas.edit == null) {
                    toast (_("Click in a text frame first"));
                    return;
                }
                string s = "";
                switch (v.get_string ()) {
                    case "shy": s = "\u00AD"; break;
                    case "nbsp": s = "\u00A0"; break;
                    case "emsp": s = "\u2003"; break;
                    case "ensp": s = "\u2002"; break;
                    case "lsep": s = "\u2028"; break;
                    case "tab": s = "\t"; break;
                    case "bullet": s = "•"; break;
                    case "copy": s = "©"; break;
                    case "reg": s = "®"; break;
                    case "tm": s = "™"; break;
                }
                canvas.insert_text (s);
            });
            add_action (ch);
            doc_actions += "insert-char";
            act ("bold", () => {
                int v = current_chars ().bold == 1 ? 0 : 1;
                format_runs (_("Bold"), (r) => r.fmt.bold = v);
            });
            act ("italic", () => {
                int v = current_chars ().italic == 1 ? 0 : 1;
                format_runs (_("Italic"), (r) => r.fmt.italic = v);
            });
            act ("underline", () => {
                int v = current_chars ().underline == 1 ? 0 : 1;
                format_runs (_("Underline"), (r) => r.fmt.underline = v);
            });
            act ("strike", () => {
                int v = current_chars ().strike == 1 ? 0 : 1;
                format_runs (_("Strikethrough"), (r) => r.fmt.strike = v);
            });
            act ("superscript", () => {
                int v = current_chars ().position == 1 ? 0 : 1;
                format_runs (_("Superscript"), (r) => r.fmt.position = v);
            });
            act ("subscript", () => {
                int v = current_chars ().position == 2 ? 0 : 2;
                format_runs (_("Subscript"), (r) => r.fmt.position = v);
            });
            act ("all-caps", () => {
                int v = current_chars ().caps == 1 ? 0 : 1;
                format_runs (_("All Caps"), (r) => r.fmt.caps = v);
            });
            act ("small-caps", () => {
                int v = current_chars ().caps == 2 ? 0 : 2;
                format_runs (_("Small Caps"), (r) => r.fmt.caps = v);
            });
            act ("font-bigger", () => font_step (true));
            act ("font-smaller", () => font_step (false));
            act ("align-left", () => format_paras (_("Align"), (p) => p.fmt.align = (int) TextAlign.LEFT));
            act ("align-center", () => format_paras (_("Align"), (p) => p.fmt.align = (int) TextAlign.CENTER));
            act ("align-right", () => format_paras (_("Align"), (p) => p.fmt.align = (int) TextAlign.RIGHT));
            act ("align-justify", () => format_paras (_("Align"), (p) => p.fmt.align = (int) TextAlign.JUSTIFY));
            act ("align-justify-all", () => format_paras (_("Align"), (p) => p.fmt.align = (int) TextAlign.JUSTIFY_ALL));
            act ("bullets", () => {
                int v = current_para_format ().list_type == 1 ? 0 : 1;
                format_paras (_("Bullets"), (p) => {
                    p.fmt.list_type = v;
                    if (v == 1 && current_para_format ().left_indent < 1) {
                        p.fmt.left_indent = 14;
                        p.fmt.first_indent = -10;
                    }
                });
            });
            act ("numbering", () => {
                int v = current_para_format ().list_type == 2 ? 0 : 2;
                format_paras (_("Numbering"), (p) => {
                    p.fmt.list_type = v;
                    if (v == 2 && current_para_format ().left_indent < 1) {
                        p.fmt.left_indent = 18;
                        p.fmt.first_indent = -14;
                    }
                });
            });
            act ("drop-cap", () => {
                int v = current_para_format ().drop_lines >= 2 ? 0 : 3;
                format_paras (_("Drop Cap"), (p) => {
                    p.fmt.drop_lines = v;
                    p.fmt.drop_chars = 1;
                });
            });
            act ("hyphenate", () => {
                int v = current_para_format ().hyphenate == 1 ? 0 : 1;
                format_paras (_("Hyphenation"), (p) => p.fmt.hyphenate = v);
                if (v == 1) toast (Hyphenator.describe (current_chars ().lang ?? "en"));
            });
            act ("align-grid", () => {
                int v = current_para_format ().align_grid == 1 ? 0 : 1;
                format_paras (_("Align to Baseline Grid"), (p) => p.fmt.align_grid = v);
            });
            act ("clear-overrides", () => {
                format_paras (_("Clear Overrides"), (p) => {
                    p.fmt = new ParaFormat ();
                    foreach (var r in p.runs) {
                        r.fmt = new CharFormat ();
                        r.cstyle = "";
                    }
                });
            });
            act ("frame-options", () => {
                toggle_panel ("format", true);
            });
            act ("fit-frame", () => fit_frame_to_text ());
            act ("thread-new", () => thread_to_new ());
            act ("unthread", () => {
                var t = single_text_frame ();
                if (t == null) return;
                edit (_("Unthread"), () => doc.pub.unlink_after (t));
                canvas.invalidate ();
            });
            act ("detach-frame", () => {
                var t = single_text_frame ();
                if (t == null) return;
                edit (_("Remove Frame from Thread"), () => doc.pub.detach_frame (t));
                canvas.invalidate ();
            });
            act ("bring-front", () => reorder (2));
            act ("bring-forward", () => reorder (1));
            act ("send-backward", () => reorder (-1));
            act ("send-back", () => reorder (-2));
            act ("arrange-left", () => align_objects (0));
            act ("arrange-center", () => align_objects (1));
            act ("arrange-right", () => align_objects (2));
            act ("arrange-top", () => align_objects (3));
            act ("arrange-middle", () => align_objects (4));
            act ("arrange-bottom", () => align_objects (5));
            act ("distribute-h", () => distribute (true));
            act ("distribute-v", () => distribute (false));
            var align_to = new SimpleAction.stateful ("align-to", VariantType.STRING, new Variant.string ("selection"));
            align_to.activate.connect ((v) => align_to.set_state (v));
            add_action (align_to);
            act ("group", () => group_selection ());
            act ("ungroup", () => ungroup_selection ());
            act ("lock", () => {
                bool lk = sel ().size > 0 && !sel ()[0].locked;
                edit (lk ? _("Lock") : _("Unlock"), () => {
                    foreach (var it in sel ()) it.locked = lk;
                });
                inspector.rebuild ();
            });
            act ("unlock-all", () => edit (_("Unlock All"), () => {
                foreach (var it in canvas.active_list ()) it.locked = false;
            }));
            act ("hide", () => {
                var items = new Gee.ArrayList<Item> ();
                items.add_all (sel ());
                edit (_("Hide"), () => {
                    foreach (var it in items) it.hidden = true;
                });
                canvas.select_only (null);
            });
            act ("show-all", () => edit (_("Show All"), () => {
                foreach (var it in canvas.active_list ()) it.hidden = false;
            }));
            var wrap = new SimpleAction ("wrap", VariantType.STRING);
            wrap.activate.connect ((v) => {
                if (doc == null || sel ().size == 0) return;
                var m = WrapMode.parse (v.get_string ());
                edit (_("Text Wrap"), () => {
                    foreach (var it in sel ()) it.wrap = m;
                });
                inspector.rebuild ();
            });
            add_action (wrap);
            doc_actions += "wrap";
            act ("fit-fill", () => set_fit (FitMode.FILL));
            act ("fit-content", () => set_fit (FitMode.FIT));
            act ("fit-stretch", () => set_fit (FitMode.STRETCH));
            act ("fit-center", () => center_content ());
            act ("fit-frame-content", () => frame_to_content ());
            act ("flip-h", () => edit (_("Flip"), () => {
                foreach (var it in sel ()) it.flip_h = !it.flip_h;
            }));
            act ("flip-v", () => edit (_("Flip"), () => {
                foreach (var it in sel ()) it.flip_v = !it.flip_v;
            }));
            act ("rotate-cw", () => edit (_("Rotate"), () => {
                foreach (var it in sel ()) it.rotation = Math.fmod (it.rotation + 90 + 360, 360);
            }));
            act ("rotate-ccw", () => edit (_("Rotate"), () => {
                foreach (var it in sel ()) it.rotation = Math.fmod (it.rotation + 270, 360);
            }));
            act ("relink", () => {
                var im = single_image ();
                if (im != null) relink.begin (im);
            });
            act ("embed", () => {
                var im = single_image ();
                if (im != null) embed_image (im);
            });
            act ("override-master", () => override_all_master_items ());
            act ("nonprinting", () => {
                bool v = sel ().size > 0 && !sel ()[0].nonprinting;
                edit (_("Nonprinting"), () => {
                    foreach (var it in sel ()) it.nonprinting = v;
                });
            });
            act ("add-page", () => add_pages (doc.current_page + 1, 1, null));
            act ("insert-pages", () => Dialogs.insert_pages (this));
            act ("duplicate-page", () => duplicate_page (doc.current_page));
            act ("delete-page", () => delete_page (doc.current_page));
            act ("page-up", () => move_page (doc.current_page, doc.current_page - 1));
            act ("page-down", () => move_page (doc.current_page, doc.current_page + 1));
            act ("new-master", () => new_master ());
            act ("edit-masters", () => set_master_mode (!canvas.master_mode));
            act ("sections", () => Dialogs.sections (this, doc.current_page));
            act ("create-guides", () => Dialogs.create_guides (this));
            act ("clear-guides", () => {
                var sl = canvas.active_slot ();
                if (sl == null) return;
                edit (_("Clear Guides"), () => canvas.own_guides (sl).clear ());
            });
            act ("first-page", () => go_to_page (0));
            act ("last-page", () => go_to_page (doc.pub.pages.size - 1));
            act ("prev-page", () => go_to_page (doc.current_page - 1));
            act ("next-page", () => go_to_page (doc.current_page + 1));
            act ("go-to-page", () => Dialogs.go_to_page (this));
            act ("table-row-above", () => table_op (0));
            act ("table-row-below", () => table_op (1));
            act ("table-row-delete", () => table_op (2));
            act ("table-col-left", () => table_op (3));
            act ("table-col-right", () => table_op (4));
            act ("table-col-delete", () => table_op (5));
            act ("table-merge", () => table_op (6));
            act ("table-split", () => table_op (7));
            act ("table-distribute", () => table_op (8));
            act ("merge-csv", () => merge_panel.choose_csv ());
            act ("merge-contacts", () => merge_panel.use_contacts ());
            act ("merge-remove", () => {
                edit (_("Remove Data Source"), () => Merge.clear_source (doc.pub));
                merge_panel.rebuild ();
            });
            toggle_act ("merge-preview", false, (v) => {
                if (!doc.pub.merge.active ()) {
                    set_toggle_state ("merge-preview", false);
                    toast (_("Choose a data source first"));
                    return;
                }
                doc.pub.merge.preview = v ? 0 : -1;
                content_edited ();
                merge_panel.rebuild ();
            });
            act ("merge-first", () => merge_panel.go (0));
            act ("merge-prev", () => merge_panel.step (-1));
            act ("merge-next", () => merge_panel.step (1));
            act ("merge-last", () => merge_panel.go (doc.pub.merge.records.size - 1));
            toggle_act ("merge-catalogue", false, (v) => {
                edit (_("Catalogue Merge"), () => doc.pub.merge.catalogue = v);
                merge_panel.rebuild ();
            });
            act ("merge-area", () => merge_panel.area_from_selection ());
            act ("merge-pdf", () => merge_panel.merge_pdf ());
            act ("merge-new", () => merge_panel.merge_new ());
            act ("merge-print", () => merge_panel.merge_print ());
            ProActions.install (this);
            sync_actions ();
        }

        public TextFrame? single_text_frame () {
            if (canvas.edit != null && canvas.edit.frame != null) return canvas.edit.frame;
            if (sel ().size == 1 && sel ()[0] is TextFrame) return (TextFrame) sel ()[0];
            return null;
        }

        public ImageFrame? single_image () {
            if (sel ().size == 1 && sel ()[0] is ImageFrame) return (ImageFrame) sel ()[0];
            return null;
        }

        public Story? current_story () {
            if (canvas.edit != null) return canvas.edit.story;
            var t = single_text_frame ();
            return t != null ? doc.pub.story (t.story) : null;
        }

        public Rect default_frame_rect (double w, double h) {
            var pr = doc.pub.page_rect ();
            int pi = canvas.active_page_index ();
            var m = pi >= 0 ? doc.pub.margin_rect (pi) : doc.pub.margin_rect (0);
            double fw = double.min (w, m.w), fh = double.min (h, m.h);
            paste_offset = (paste_offset + 12) % 96;
            return Rect (m.x + (m.w - fw) / 2 + paste_offset - 48, m.y + (m.h - fh) / 3 + paste_offset - 48, fw, fh).x < pr.x ? Rect (m.x, m.y, fw, fh) : Rect (m.x + (m.w - fw) / 2, m.y + (m.h - fh) / 3, fw, fh);
        }

        public void add_item (Item it, string label) {
            edit (label, () => canvas.active_list ().add (it));
            canvas.select_only (it);
        }

        private void insert_frame (Tool t) {
            var r = default_frame_rect (t == Tool.TEXT ? 240 : 200, t == Tool.TEXT ? 120 : 150);
            if (t == Tool.TEXT) {
                TextFrame? made = null;
                edit (_("Insert Text Frame"), () => made = doc.pub.add_text_frame (canvas.active_list (), r.x, r.y, r.w, r.h));
                canvas.select_only (made);
                canvas.begin_edit (made);
                return;
            }
            var im = new ImageFrame ();
            im.id = doc.pub.next_id ();
            im.x = r.x;
            im.y = r.y;
            im.w = r.w;
            im.h = r.h;
            im.layer = doc.pub.default_layer ().id;
            add_item (im, _("Insert Image Frame"));
        }

        private void insert_shape (ShapeKind k) {
            var r = default_frame_rect (120, k == ShapeKind.LINE ? 0 : 120);
            var s = new ShapeItem (k);
            s.id = doc.pub.next_id ();
            s.x = r.x;
            s.y = r.y;
            s.w = r.w;
            s.h = k == ShapeKind.LINE ? 0 : r.h;
            s.layer = doc.pub.default_layer ().id;
            s.stroke = new Stroke.with (ColorRef.BLACK, 1);
            if (k != ShapeKind.LINE) s.fill = new Fill.solid (ColorRef.swatch ("Cyan", 20));
            if (k == ShapeKind.STAR) s.sides = 5;
            add_item (s, _("Insert Shape"));
        }

        public void insert_table (int rows, int cols, int header) {
            var m = doc.pub.margin_rect (int.max (0, canvas.active_page_index ()));
            double w = m.w, h = double.min (rows * 22.0, m.h);
            var tb = new TableItem (rows, cols);
            tb.id = doc.pub.next_id ();
            tb.x = m.x;
            tb.y = m.y + 20;
            tb.w = w;
            tb.h = h;
            tb.header_rows = header;
            tb.header_fill = header > 0 ? ColorRef.swatch ("Black", 12) : ColorRef.NONE;
            tb.alt_fill = ColorRef.swatch ("Cyan", 6);
            tb.layer = doc.pub.default_layer ().id;
            tb.init_cells (doc.pub);
            add_item (tb, _("Insert Table"));
        }

        public void insert_field_or_frame (string field) {
            if (canvas.edit != null) {
                canvas.insert_field (field);
                return;
            }
            var r = default_frame_rect (80, 24);
            TextFrame? made = null;
            edit (_("Insert Field"), () => {
                made = doc.pub.add_text_frame (canvas.active_list (), r.x, r.y, r.w, r.h);
                var st = doc.pub.story (made.story);
                st.insert_field (TextPos (0, 0), field);
            });
            canvas.select_only (made);
        }

        public async void place () {
            var dialog = new FileDialog ();
            dialog.title = _("Place Pictures");
            var f = new FileFilter ();
            f.name = _("Pictures, PDF and Atelier Files");
            f.add_mime_type ("image/*");
            f.add_mime_type ("application/pdf");
            f.add_suffix ("pdf");
            f.add_suffix ("svg");
            f.add_suffix ("atelier");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (f);
            dialog.filters = filters;
            try {
                var files = yield dialog.open_multiple (this, null);
                if (files == null) return;
                File[] list = {};
                for (uint i = 0; i < files.get_n_items (); i++) list += (File) files.get_item (i);
                place_files (list);
            } catch (Error e) {
            }
        }

        public void place_files (File[] files) {
            if (doc == null) return;
            bool link = app.get_bool ("link-images", true);
            var target = single_image ();
            var placed = new Gee.ArrayList<Item> ();
            doc.checkpoint (_("Place"));
            bool several = files.length > 1 && target == null;
            var empty = several ? PicturePlacement.empty_frames (canvas.active_list ()) : new Gee.ArrayList<ImageFrame> ();
            int k = 0, to_scratch = 0;
            foreach (var file in files) {
                string? path = file.get_path ();
                if (path == null) continue;
                uint8[] data;
                try {
                    FileUtils.get_data (path, out data);
                } catch (Error e) {
                    continue;
                }
                var inf = ImageStore.decode (data);
                if (inf == null) {
                    toast (_("\"%s\" is not an image Publish can read").printf (file.get_basename ()));
                    continue;
                }
                ImageFrame im;
                if (target != null && k == 0) {
                    im = target;
                } else if (several && k < empty.size) {
                    im = empty[k];
                } else if (several) {
                    im = new ImageFrame ();
                    im.id = doc.pub.next_id ();
                    var slot = PicturePlacement.scratch_slot (doc.pub, canvas.active_list (), 0);
                    double nat_w = inf.width * 72.0 / inf.dpi, nat_h = inf.height * 72.0 / inf.dpi;
                    double sc = double.min (slot.w / nat_w, slot.h / nat_h);
                    im.w = nat_w * sc;
                    im.h = nat_h * sc;
                    im.x = slot.x;
                    im.y = slot.y;
                    im.fit = FitMode.FIT;
                    im.layer = doc.pub.default_layer ().id;
                    canvas.active_list ().add (im);
                    to_scratch++;
                } else {
                    im = new ImageFrame ();
                    im.id = doc.pub.next_id ();
                    double nat_w = inf.width * 72.0 / inf.dpi, nat_h = inf.height * 72.0 / inf.dpi;
                    var m = doc.pub.margin_rect (int.max (0, canvas.active_page_index ()));
                    double sc = double.min (1, double.min (m.w / nat_w, m.h / nat_h));
                    im.w = nat_w * sc;
                    im.h = nat_h * sc;
                    im.x = m.x + k * 18;
                    im.y = m.y + k * 18;
                    im.fit = FitMode.FIT;
                    im.layer = doc.pub.default_layer ().id;
                    canvas.active_list ().add (im);
                }
                if (link) {
                    im.link = path;
                    im.link_stamp = ImageStore.stamp_for (path);
                    im.media = "";
                } else {
                    im.link = "";
                    im.media = doc.pub.add_media (data, file.get_basename ());
                }
                placed.add (im);
                k++;
            }
            if (placed.size == 0) {
                doc.drop_checkpoint ();
                return;
            }
            doc.touch ();
            content_edited ();
            if (to_scratch > 0) toast (ngettext ("%d picture is waiting beside the page; swap it into a frame when you need it", "%d pictures are waiting beside the page; swap them into frames when you need them", to_scratch).printf (to_scratch));
            canvas.selection.clear ();
            canvas.selection.add_all (placed);
            canvas.selection_changed ();
            links_panel.rebuild ();
        }

        public async void relink (ImageFrame im) {
            var dialog = new FileDialog ();
            dialog.title = _("Relink Image");
            dialog.initial_folder = default_folder ();
            try {
                var file = yield dialog.open (this, null);
                if (file == null || file.get_path () == null) return;
                edit (_("Relink"), () => {
                    im.link = file.get_path ();
                    im.link_stamp = ImageStore.stamp_for (im.link);
                    im.media = "";
                });
                links_panel.rebuild ();
            } catch (Error e) {
            }
        }

        public void update_link (ImageFrame im) {
            string p = ImageStore.resolve_link (doc.pub, im.link);
            edit (_("Update Link"), () => im.link_stamp = ImageStore.stamp_for (p));
            ImageStore.get_default ().clear ();
            content_edited ();
        }

        public void embed_image (ImageFrame im) {
            var data = ImageStore.get_default ().bytes_for (doc.pub, im);
            if (data == null) {
                toast (_("The image is missing and cannot be embedded"));
                return;
            }
            string name = im.link != "" ? Path.get_basename (im.link) : "image.png";
            edit (_("Embed Image"), () => {
                im.media = doc.pub.add_media (data, name);
                im.link = "";
                im.link_stamp = "";
            });
            links_panel.rebuild ();
        }

        public void unembed_image (ImageFrame im) {
            if (im.media == "" || !doc.pub.media.has_key (im.media)) return;
            string ext = im.media.substring (im.media.last_index_of (".") + 1);
            var dir = default_folder ().get_path ();
            string path = Path.build_filename (dir, "%s-%d.%s".printf (base_name (_("Publication")), im.id, ext));
            try {
                FileUtils.set_data (path, doc.pub.media[im.media].get_data ());
                edit (_("Unembed Image"), () => {
                    im.link = path;
                    im.link_stamp = ImageStore.stamp_for (path);
                    im.media = "";
                    doc.pub.prune_media ();
                });
                links_panel.rebuild ();
                toast (_("Saved the image as \"%s\"").printf (Path.get_basename (path)));
            } catch (Error e) {
                show_error (_("Could Not Unembed"), e.message);
            }
        }

        private async void package () {
            if (doc == null) return;
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Folder for the Package");
            dialog.initial_folder = default_folder ();
            try {
                var folder = yield dialog.select_folder (this, null);
                if (folder == null) return;
                string name = base_name (_("Publication"));
                string root = Path.build_filename (folder.get_path (), name + " " + _("Package"));
                int n = 2;
                while (FileUtils.test (root, FileTest.EXISTS)) root = Path.build_filename (folder.get_path (), "%s %s %d".printf (name, _("Package"), n++));
                var links_dir = Path.build_filename (root, "Links");
                DirUtils.create_with_parents (links_dir, 0755);
                var copy = doc.pub.clone ();
                int copied = 0, missing = 0;
                var report = new StringBuilder ();
                report.append (_("Package report for %s").printf (name) + "\n\n");
                copy.walk ((r) => {
                    var im = r.item as ImageFrame;
                    if (im == null || im.link == "") return true;
                    string src = ImageStore.resolve_link (doc.pub, im.link);
                    if (!FileUtils.test (src, FileTest.IS_REGULAR)) {
                        missing++;
                        report.append (_("Missing: %s").printf (im.link) + "\n");
                        return true;
                    }
                    string dst = Path.build_filename (links_dir, Path.get_basename (src));
                    try {
                        File.new_for_path (src).copy (File.new_for_path (dst), FileCopyFlags.OVERWRITE);
                        im.link = Path.build_filename ("Links", Path.get_basename (src));
                        im.link_stamp = ImageStore.stamp_for (dst);
                        copied++;
                    } catch (Error e) {
                        missing++;
                    }
                    return true;
                });
                copy.base_dir = root;
                string doc_path = Path.build_filename (root, name + "." + NativeFormat.EXT);
                FileUtils.set_data (doc_path, NativeFormat.write (copy));
                var fonts = FontPackager.collect (copy.used_fonts (), Path.build_filename (root, "Fonts"));
                int font_files = 0;
                report.append ("\n" + _("Fonts used:") + "\n");
                foreach (string f in copy.used_fonts ()) {
                    bool found = false;
                    foreach (var pf in fonts) {
                        if (pf.family != f) continue;
                        found = true;
                        if (pf.copied) font_files++;
                        report.append ("  %s: %s (%s)\n".printf (f, Path.get_basename (pf.file), pf.licence.label ()));
                    }
                    if (!found) report.append ("  %s (%s)\n".printf (f, _("not installed, not copied")));
                }
                string pdf_note = "";
                try {
                    var po = new ExportOptions ();
                    po.crop_marks = true;
                    po.bleed_marks = true;
                    po.color_mode = copy.settings.cmyk ? ColorMode.CMYK : ColorMode.RGB;
                    var ex = new Exporter (copy, po);
                    ex.export_pdf (Path.build_filename (root, name + ".pdf"));
                    pdf_note = _("A print PDF of the publication is included.");
                } catch (Error e) {
                    pdf_note = _("The print PDF could not be written: %s").printf (e.message);
                }
                report.append ("\n" + _("Linked images copied: %d").printf (copied) + "\n");
                report.append (_("Missing images: %d").printf (missing) + "\n");
                report.append (_("Font files copied: %d").printf (font_files) + "\n");
                report.append ("\n" + pdf_note + "\n");
                report.append (_("Fonts whose licence forbids embedding are listed but not copied.") + "\n");
                FileUtils.set_contents (Path.build_filename (root, _("Instructions") + ".txt"), report.str);
                toast (_("Packaged \"%s\" with %d linked images and %d font files").printf (name, copied, font_files));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Package"), e.message);
            }
        }

        private void copy_text () {
            var frag = canvas.selected_fragment ();
            if (frag == null) return;
            text_clip = frag;
            text_clip_plain = canvas.selected_text ();
            get_clipboard ().set_text (text_clip_plain);
        }

        private void copy_items () {
            if (sel ().size == 0) return;
            item_clip.clear ();
            item_clip_stories.clear ();
            item_clip_media.clear ();
            var texts = new StringBuilder ();
            foreach (var it in sel ()) {
                item_clip.add (it.clone ());
                collect_clip (it, texts);
            }
            text_clip = null;
            text_clip_plain = "\x01items\x01" + texts.str;
            get_clipboard ().set_text (texts.str);
        }

        private void collect_clip (Item it, StringBuilder texts) {
            var t = it as TextFrame;
            if (t != null && doc.pub.stories.has_key (t.story)) {
                item_clip_stories[t.story] = doc.pub.stories[t.story].clone ();
                if (texts.len > 0) texts.append ("\n");
                texts.append (doc.pub.stories[t.story].plain_text ());
            }
            var im = it as ImageFrame;
            if (im != null && im.media != "" && doc.pub.media.has_key (im.media)) item_clip_media[im.media] = doc.pub.media[im.media];
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) collect_clip (c, texts);
        }

        private void adopt_clip_item (Item it) {
            var t = it as TextFrame;
            if (t != null) {
                var src = item_clip_stories.has_key (t.story) ? item_clip_stories[t.story].clone () : new Story (0);
                src.id = doc.pub.next_id ();
                src.frames.clear ();
                src.frames.add (t.id);
                doc.pub.stories[src.id] = src;
                t.story = src.id;
            }
            var im = it as ImageFrame;
            if (im != null && im.media != "" && item_clip_media.has_key (im.media)) doc.pub.media[im.media] = item_clip_media[im.media];
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) {
                c.id = doc.pub.next_id ();
                adopt_clip_item (c);
            }
            if (doc.pub.layer (it.layer) == null) it.layer = doc.pub.default_layer ().id;
        }

        private async void paste (bool in_place) {
            if (canvas.edit != null) {
                string? text = null;
                try {
                    text = yield get_clipboard ().read_text_async (null);
                } catch (Error e) {
                }
                if (item_clip.size > 0 && text_clip_plain.has_prefix ("\x01items\x01") && (text == null || text == text_clip_plain)) {
                    var frag = new Story (0);
                    frag.paras.clear ();
                    var para = new Paragraph ();
                    para.runs.clear ();
                    foreach (var src in item_clip) {
                        var it = src.clone ();
                        it.id = doc.pub.next_id ();
                        adopt_clip_item (it);
                        it.x = 0;
                        it.y = 0;
                        var g = it as GroupItem;
                        if (g != null) {
                            var bb = g.bounds ();
                            g.move_by (-bb.x, -bb.y);
                        }
                        para.runs.add (new Run.anchored (it, new AnchorSpec ()));
                    }
                    frag.paras.add (para);
                    canvas.paste_fragment (frag);
                    return;
                }
                if (text_clip != null && text != null && text == text_clip_plain) canvas.paste_fragment (text_clip.clone ());
                else if (text != null) canvas.insert_text (text.replace ("\r\n", "\n"));
                return;
            }
            if (item_clip.size > 0 && text_clip_plain.has_prefix ("\x01items\x01")) {
                var pasted = new Gee.ArrayList<Item> ();
                edit (_("Paste"), () => {
                    foreach (var src in item_clip) {
                        var it = src.clone ();
                        it.id = doc.pub.next_id ();
                        adopt_clip_item (it);
                        if (!in_place) {
                            var g = it as GroupItem;
                            if (g != null) g.move_by (12, 12);
                            else {
                                it.x += 12;
                                it.y += 12;
                            }
                        }
                        canvas.active_list ().add (it);
                        pasted.add (it);
                    }
                });
                canvas.selection.clear ();
                canvas.selection.add_all (pasted);
                canvas.selection_changed ();
                return;
            }
            try {
                var tex = yield get_clipboard ().read_texture_async (null);
                if (tex != null) {
                    var bytes = tex.save_to_png_bytes ();
                    var im = new ImageFrame ();
                    im.id = doc.pub.next_id ();
                    im.media = doc.pub.add_media (bytes.get_data (), "pasted.png");
                    var r = default_frame_rect (tex.width * 0.75, tex.height * 0.75);
                    im.x = r.x;
                    im.y = r.y;
                    im.w = r.w;
                    im.h = r.h;
                    im.fit = FitMode.FIT;
                    im.layer = doc.pub.default_layer ().id;
                    add_item (im, _("Paste"));
                    return;
                }
            } catch (Error e) {
            }
            try {
                string? text = yield get_clipboard ().read_text_async (null);
                if (text == null || text == "") return;
                var r = default_frame_rect (240, 120);
                TextFrame? made = null;
                edit (_("Paste"), () => {
                    made = doc.pub.add_text_frame (canvas.active_list (), r.x, r.y, r.w, r.h);
                    doc.pub.story (made.story).insert_text (TextPos (0, 0), text);
                });
                canvas.select_only (made);
            } catch (Error e) {
            }
        }

        public void duplicate_items (double dx, double dy, int count) {
            if (sel ().size == 0) return;
            var made = new Gee.ArrayList<Item> ();
            var src = new Gee.ArrayList<Item> ();
            src.add_all (sel ());
            edit (count > 1 ? _("Step and Repeat") : _("Duplicate"), () => {
                for (int k = 1; k <= count; k++) {
                    foreach (var it in src) {
                        var c = it.clone ();
                        doc.pub.reassign (c);
                        var g = c as GroupItem;
                        if (g != null) g.move_by (dx * k, dy * k);
                        else {
                            c.x += dx * k;
                            c.y += dy * k;
                        }
                        canvas.active_list ().add (c);
                        made.add (c);
                    }
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (made);
            canvas.selection_changed ();
        }

        private void delete_items (string label) {
            if (sel ().size == 0) return;
            var items = new Gee.ArrayList<Item> ();
            items.add_all (sel ());
            edit (label, () => {
                var list = canvas.active_list ();
                foreach (var it in items) list.remove (it);
                doc.pub.prune_stories ();
            });
            canvas.select_only (null);
        }

        private void reorder (int mode) {
            var list = canvas.active_list ();
            var items = new Gee.ArrayList<Item> ();
            foreach (var it in list) if (sel ().contains (it)) items.add (it);
            if (items.size == 0) return;
            edit (_("Arrange"), () => {
                switch (mode) {
                    case 2:
                        foreach (var it in items) {
                            list.remove (it);
                            list.add (it);
                        }
                        break;
                    case -2:
                        for (int i = items.size - 1; i >= 0; i--) {
                            list.remove (items[i]);
                            list.insert (0, items[i]);
                        }
                        break;
                    case 1:
                        for (int i = items.size - 1; i >= 0; i--) {
                            int idx = list.index_of (items[i]);
                            if (idx < list.size - 1 && !items.contains (list[idx + 1])) {
                                list.remove_at (idx);
                                list.insert (idx + 1, items[i]);
                            }
                        }
                        break;
                    default:
                        foreach (var it in items) {
                            int idx = list.index_of (it);
                            if (idx > 0 && !items.contains (list[idx - 1])) {
                                list.remove_at (idx);
                                list.insert (idx - 1, it);
                            }
                        }
                        break;
                }
            });
        }

        private Rect align_reference () {
            var a = lookup_action ("align-to") as SimpleAction;
            string mode = a != null ? a.get_state ().get_string () : "selection";
            int pi = canvas.active_page_index ();
            if (mode == "margins") return doc.pub.margin_rect (int.max (0, pi));
            if (mode == "page" || (mode == "selection" && sel ().size == 1)) return doc.pub.page_rect ();
            if (mode == "spread") {
                var pr = doc.pub.page_rect ();
                if (!doc.pub.settings.facing || pi < 0) return pr;
                var sp = doc.pub.spreads ()[doc.pub.spread_of (pi)];
                if (sp.pages.size < 2) return pr;
                bool left = doc.pub.is_left_page (pi);
                return left ? Rect (0, 0, pr.w * 2, pr.h) : Rect (-pr.w, 0, pr.w * 2, pr.h);
            }
            return canvas.selection_bounds ();
        }

        private void align_objects (int mode) {
            if (sel ().size == 0) return;
            var ref_r = align_reference ();
            edit (_("Align"), () => {
                foreach (var it in sel ()) {
                    var b = it.bounds ();
                    double dx = 0, dy = 0;
                    switch (mode) {
                        case 0: dx = ref_r.x - b.x; break;
                        case 1: dx = ref_r.x + ref_r.w / 2 - (b.x + b.w / 2); break;
                        case 2: dx = ref_r.x2 () - b.x2 (); break;
                        case 3: dy = ref_r.y - b.y; break;
                        case 4: dy = ref_r.y + ref_r.h / 2 - (b.y + b.h / 2); break;
                        default: dy = ref_r.y2 () - b.y2 (); break;
                    }
                    move_item (it, dx, dy);
                }
            });
        }

        private static void move_item (Item it, double dx, double dy) {
            var g = it as GroupItem;
            if (g != null) g.move_by (dx, dy);
            else {
                it.x += dx;
                it.y += dy;
            }
        }

        private void distribute (bool horizontal) {
            if (sel ().size < 3) {
                toast (_("Select at least three objects to distribute"));
                return;
            }
            var items = new Gee.ArrayList<Item> ();
            items.add_all (sel ());
            items.sort ((a, b) => {
                double va = horizontal ? a.bounds ().x : a.bounds ().y, vb = horizontal ? b.bounds ().x : b.bounds ().y;
                return va < vb ? -1 : (va > vb ? 1 : 0);
            });
            edit (_("Distribute"), () => {
                double total = 0;
                foreach (var it in items) total += horizontal ? it.bounds ().w : it.bounds ().h;
                var f = items[0].bounds ();
                var l = items[items.size - 1].bounds ();
                double span = horizontal ? l.x2 () - f.x : l.y2 () - f.y;
                double gap = (span - total) / (items.size - 1);
                double pos = horizontal ? f.x : f.y;
                foreach (var it in items) {
                    var b = it.bounds ();
                    if (horizontal) move_item (it, pos - b.x, 0);
                    else move_item (it, 0, pos - b.y);
                    pos += (horizontal ? b.w : b.h) + gap;
                }
            });
        }

        private void group_selection () {
            if (sel ().size < 2) return;
            var list = canvas.active_list ();
            var items = new Gee.ArrayList<Item> ();
            foreach (var it in list) if (sel ().contains (it)) items.add (it);
            var g = new GroupItem ();
            edit (_("Group"), () => {
                g.id = doc.pub.next_id ();
                g.layer = items[items.size - 1].layer;
                int at = list.index_of (items[items.size - 1]);
                foreach (var it in items) {
                    list.remove (it);
                    g.children.add (it);
                }
                g.fit_children ();
                at = int.min (at - items.size + 1, list.size);
                list.insert (int.max (0, at), g);
            });
            canvas.select_only (g);
        }

        private void ungroup_selection () {
            var list = canvas.active_list ();
            var made = new Gee.ArrayList<Item> ();
            var groups = new Gee.ArrayList<GroupItem> ();
            foreach (var it in sel ()) if (it is GroupItem) groups.add ((GroupItem) it);
            if (groups.size == 0) return;
            edit (_("Ungroup"), () => {
                foreach (var g in groups) {
                    int at = list.index_of (g);
                    list.remove (g);
                    foreach (var c in g.children) {
                        if (g.rotation != 0) {
                            var cp = c.center ();
                            var np = rotate_point (cp, g.center (), g.rotation);
                            move_item (c, np.x - cp.x, np.y - cp.y);
                            c.rotation = Math.fmod (c.rotation + g.rotation, 360);
                        }
                        if (g.opacity < 1) c.opacity *= g.opacity;
                        list.insert (at++, c);
                        made.add (c);
                    }
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (made);
            canvas.selection_changed ();
        }

        private static Point rotate_point (Point p, Point c, double deg) {
            double a = deg * Math.PI / 180;
            double dx = p.x - c.x, dy = p.y - c.y;
            return Point (c.x + dx * Math.cos (a) - dy * Math.sin (a), c.y + dx * Math.sin (a) + dy * Math.cos (a));
        }

        private void set_fit (FitMode m) {
            var ims = new Gee.ArrayList<ImageFrame> ();
            foreach (var it in sel ()) if (it is ImageFrame) ims.add ((ImageFrame) it);
            if (ims.size == 0) return;
            edit (_("Fitting"), () => {
                foreach (var im in ims) {
                    im.fit = m;
                    im.focus_x = 0.5;
                    im.focus_y = 0.5;
                }
            });
            inspector.rebuild ();
        }

        private void center_content () {
            var im = single_image ();
            if (im == null) return;
            var inf = ImageStore.get_default ().info (doc.pub, im);
            if (inf == null) return;
            edit (_("Center Content"), () => {
                if (im.fit == FitMode.MANUAL) {
                    var pl = ImageStore.place (im, inf);
                    im.img_x = (im.w - inf.width * pl.sx) / 2;
                    im.img_y = (im.h - inf.height * pl.sy) / 2;
                } else {
                    im.focus_x = 0.5;
                    im.focus_y = 0.5;
                }
            });
        }

        private void frame_to_content () {
            var im = single_image ();
            if (im == null) return;
            var inf = ImageStore.get_default ().info (doc.pub, im);
            if (inf == null) return;
            edit (_("Fit Frame to Content"), () => {
                var pl = ImageStore.place (im, inf);
                double w = inf.width * pl.sx, h = inf.height * pl.sy;
                var p = im.to_page (pl.ox, pl.oy);
                if (im.rotation == 0) {
                    im.x = p.x;
                    im.y = p.y;
                }
                im.w = w;
                im.h = h;
                im.img_x = 0;
                im.img_y = 0;
                if (im.fit == FitMode.MANUAL) im.fit = FitMode.MANUAL;
                else im.fit = FitMode.FILL;
            });
        }

        public void fit_frame_to_text () {
            var t = single_text_frame ();
            if (t == null) return;
            var cache = canvas.cache;
            var res = cache.story (t.story);
            var fr = res.frame_result (t.id);
            if (fr == null) return;
            if (res.overset && res.frames[res.frames.size - 1].frame == t) {
                edit (_("Fit Frame to Text"), () => {
                    for (int i = 0; i < 40; i++) {
                        t.h += 24;
                        canvas.cache.invalidate ();
                        if (!canvas.cache.story (t.story).overset) break;
                    }
                });
                return;
            }
            edit (_("Fit Frame to Text"), () => t.h = double.max (12, fr.content_height + t.inset_bottom + 1));
        }

        private void thread_to_new () {
            var t = single_text_frame ();
            if (t == null) return;
            canvas.end_edit ();
            canvas.select_only (t);
            canvas.thread_from = t;
            sync_tools ();
        }

        public void override_master_item (Item it) {
            int pi = canvas.active_page_index ();
            if (pi < 0) return;
            Item? made = null;
            edit (_("Override Master Item"), () => made = doc.pub.override_master_item (pi, it));
            if (made != null) canvas.select_only (made);
        }

        private void override_all_master_items () {
            int pi = canvas.active_page_index ();
            if (pi < 0) return;
            var items = doc.pub.master_items_for (pi);
            if (items.size == 0) return;
            edit (_("Override All Master Items"), () => {
                foreach (var it in items) doc.pub.override_master_item (pi, it);
            });
        }

        public void add_pages (int at, int count, string? master) {
            string m = master ?? (doc.page != null ? doc.page.master : "A");
            edit (ngettext ("Add Page", "Add Pages", count), () => {
                for (int i = 0; i < count; i++) doc.pub.add_page (at + i, m);
            });
            canvas.relayout ();
            canvas.queue_allocate ();
            pages_panel.load ();
            go_to_page (at);
        }

        public void duplicate_page (int index) {
            if (index < 0 || index >= doc.pub.pages.size) return;
            edit (_("Duplicate Page"), () => {
                var src = doc.pub.pages[index];
                var pg = doc.pub.add_page (index + 1, src.master);
                pg.hide_master = src.hide_master;
                foreach (var g in src.guides) pg.guides.add (g.clone ());
                foreach (var it in src.items) {
                    var c = it.clone ();
                    doc.pub.reassign (c);
                    pg.items.add (c);
                }
            });
            canvas.relayout ();
            pages_panel.load ();
            go_to_page (index + 1);
        }

        public void delete_page (int index) {
            if (doc.pub.pages.size <= 1) {
                toast (_("A publication needs at least one page"));
                return;
            }
            edit (_("Delete Page"), () => doc.pub.remove_page (index));
            canvas.select_only (null);
            canvas.relayout ();
            pages_panel.load ();
            go_to_page (int.min (index, doc.pub.pages.size - 1));
        }

        public void move_page (int from, int to) {
            if (to < 0 || to >= doc.pub.pages.size || from == to) return;
            edit (_("Move Page"), () => doc.pub.move_page (from, to));
            canvas.relayout ();
            pages_panel.load ();
            go_to_page (to);
        }

        public void new_master () {
            string id = doc.pub.next_master_id ();
            edit (_("New Master Page"), () => {
                var m = new MasterPage (id, _("Master"));
                doc.pub.masters.add (m);
            });
            pages_panel.load ();
            set_master_mode (true, id);
        }

        public void apply_master (int page, string master) {
            edit (_("Apply Master"), () => doc.pub.pages[page].master = master);
            pages_panel.load ();
        }

        private void table_op (int op) {
            TableItem? t = null;
            if (canvas.edit != null && canvas.edit.table != null) t = canvas.edit.table;
            else if (sel ().size == 1 && sel ()[0] is TableItem) t = (TableItem) sel ()[0];
            if (t == null) return;
            int r1 = canvas.cell_r1 >= 0 ? int.min (canvas.cell_r1, canvas.cell_r2) : 0;
            int r2 = canvas.cell_r1 >= 0 ? int.max (canvas.cell_r1, canvas.cell_r2) : 0;
            int c1 = canvas.cell_c1 >= 0 ? int.min (canvas.cell_c1, canvas.cell_c2) : 0;
            int c2 = canvas.cell_c1 >= 0 ? int.max (canvas.cell_c1, canvas.cell_c2) : 0;
            canvas.end_edit ();
            edit (_("Table"), () => {
                switch (op) {
                    case 0: t.insert_row (doc.pub, r1); break;
                    case 1: t.insert_row (doc.pub, r2 + 1); break;
                    case 2: t.delete_row (r1); break;
                    case 3: t.insert_col (doc.pub, c1); break;
                    case 4: t.insert_col (doc.pub, c2 + 1); break;
                    case 5: t.delete_col (c1); break;
                    case 6: t.merge (r1, c1, r2, c2); break;
                    case 7: t.split (r1, c1); break;
                    case 8:
                        for (int c = 0; c < t.cols; c++) t.col_w[c] = t.w / t.cols;
                        for (int r = 0; r < t.rows; r++) t.row_h[r] = t.h / t.rows;
                        break;
                }
            });
            canvas.select_only (t);
        }

        private Gee.ArrayList<Story> all_stories () {
            var list = new Gee.ArrayList<Story> ();
            var ids = new Gee.ArrayList<int> ();
            ids.add_all (doc.pub.stories.keys);
            ids.sort ((a, b) => a - b);
            foreach (int id in ids) {
                var fr = doc.pub.thread_frames (id);
                if (fr.size == 0) continue;
                list.add (doc.pub.stories[id]);
            }
            doc.pub.walk ((r) => {
                var tb = r.item as TableItem;
                if (tb != null) foreach (var row in tb.cells) foreach (var c in row) if (!c.covered) list.add (c.story);
                return true;
            });
            return list;
        }

        private class Hit {
            public Story story;
            public TextPos pos;

            public Hit (Story story, TextPos pos) {
                this.story = story;
                this.pos = pos;
            }
        }

        public bool find_case = false;
        public bool find_word = false;

        private Gee.ArrayList<Hit> find_hits (string q) {
            var hits = new Gee.ArrayList<Hit> ();
            if (q == "") return hits;
            foreach (var s in all_stories ()) foreach (var p in s.find_all (q, find_case, find_word)) hits.add (new Hit (s, p));
            return hits;
        }

        public string find_step_public (string q, int dir) {
            var hits = find_hits (q);
            if (hits.size == 0) return _("Not found");
            find_step (q, dir);
            return _("%d of %d").printf (find_index + 1, hits.size);
        }

        public string replace_one_public (string q, string r) {
            replace_one (q, r);
            int left = find_hits (q).size;
            return ngettext ("%d match left", "%d matches left", left).printf (left);
        }

        public string replace_all_public (string q, string r) {
            if (q == "") return "";
            canvas.end_edit ();
            int total = 0;
            edit (_("Replace All"), () => {
                foreach (var s in all_stories ()) total += s.replace_all (q, r, find_case, find_word);
            });
            return ngettext ("Replaced %d occurrence", "Replaced %d occurrences", total).printf (total);
        }

        public Gee.ArrayList<Story> stories_for_find () {
            return all_stories ();
        }

        public void focus_match (Story story, TextPos a, int len) {
            focus_hit (new Hit (story, a), len);
        }

        public void select_item_public (Item it) {
            var ref_ = doc.pub.find_item (it.id);
            if (ref_ != null && ref_.page != null) {
                if (canvas.master_mode) set_master_mode (false);
                go_to_page (doc.pub.pages.index_of (ref_.page));
            }
            canvas.end_edit ();
            canvas.select_only (it);
        }

        private void focus_hit (Hit h, int len) {
            TextFrame? frame = null;
            TableItem? table = null;
            int row = 0, col = 0;
            doc.pub.walk ((r) => {
                var t = r.item as TextFrame;
                if (t != null && t.story == h.story.id) {
                    if (frame == null) frame = t;
                    return true;
                }
                var tb = r.item as TableItem;
                if (tb != null) {
                    for (int i = 0; i < tb.rows; i++) for (int j = 0; j < tb.cols; j++) if (tb.cells[i][j].story == h.story) {
                        table = tb;
                        row = i;
                        col = j;
                    }
                }
                return true;
            });
            var res = canvas.cache.story (h.story.id);
            foreach (var fr in res.frames) foreach (var l in fr.lines) {
                if (l.para == h.pos.para && h.pos.offset >= l.start && h.pos.offset <= l.end && fr.frame != null) frame = fr.frame;
            }
            Item? host = frame != null ? (Item) frame : (Item) table;
            if (host == null) return;
            var ref_ = doc.pub.find_item (host.id);
            if (ref_ == null) return;
            if (ref_.page != null) {
                if (canvas.master_mode) set_master_mode (false);
                int pi = doc.pub.pages.index_of (ref_.page);
                go_to_page (pi);
            } else if (ref_.master != null) {
                set_master_mode (true, ref_.master.id);
            }
            canvas.select_only (host);
            if (frame != null) canvas.begin_edit (frame);
            else canvas.begin_cell_edit (table, row, col);
            canvas.edit.anchor = h.pos;
            canvas.edit.caret = TextPos (h.pos.para, h.pos.offset + len);
            canvas.queue_draw ();
        }

        private void find_step (string q, int dir) {
            var hits = find_hits (q);
            find_bar.set_match_info (hits.size == 0 ? 0 : 0, hits.size);
            if (hits.size == 0) return;
            find_index = (find_index + dir + hits.size) % hits.size;
            if (find_index < 0) find_index = 0;
            find_bar.set_match_info (find_index + 1, hits.size);
            focus_hit (hits[find_index], q.char_count ());
        }

        private void replace_one (string q, string r) {
            var e = canvas.edit;
            if (e != null && e.has_selection () && (find_case ? canvas.selected_text () == q : canvas.selected_text ().casefold () == q.casefold ())) {
                canvas.insert_text (r);
            }
            find_step (q, 1);
        }

        private void replace_all (string q, string r) {
            if (q == "") return;
            canvas.end_edit ();
            int total = 0;
            edit (_("Replace All"), () => {
                foreach (var s in all_stories ()) total += s.replace_all (q, r, find_case, find_word);
            });
            find_bar.set_match_info (0, 0);
            toast (ngettext ("Replaced %d occurrence", "Replaced %d occurrences", total).printf (total));
        }

        private void show_canvas_menu (double x, double y) {
            var menu = new ContextMenu (canvas);
            canvas.popup_at (menu, x, y);
            if (canvas.edit != null) {
                string word = "";
                var e = canvas.edit;
                TextPos wa, wb;
                e.story.word_bounds (e.caret, out wa, out wb);
                if (wa.offset < wb.offset) word = e.story.plain_range (wa, wb);
                var sp = Singularity.Text.SpellChecker.get_default ();
                if (word != "" && sp.available && !sp.check (word)) {
                    foreach (string s in sp.suggest (word, 5)) {
                        string ss = s;
                        menu.add_item (ss, null, () => {
                            e.anchor = wa;
                            e.caret = wb;
                            canvas.insert_text (ss);
                        });
                    }
                    string w2 = word;
                    menu.add_item (_("Add to Dictionary"), "list-add-symbolic", () => {
                        sp.add_to_dictionary (w2);
                        canvas.queue_draw ();
                    });
                    menu.add_separator ();
                }
                menu.add_item (_("Cut"), "edit-cut-symbolic", () => run ("cut"));
                menu.add_item (_("Copy"), "edit-copy-symbolic", () => run ("copy"));
                menu.add_item (_("Paste"), "edit-paste-symbolic", () => run ("paste"));
                menu.add_separator ();
                var fields = menu.add_submenu (_("Insert Field"), null);
                string[] fs = { Fields.PAGE, Fields.PAGES, Fields.SECTION, Fields.NEXT_PAGE, Fields.PREV_PAGE, Fields.DATE, Fields.TITLE };
                foreach (string f in fs) {
                    string ff = f;
                    fields.add_item (Fields.label (f), null, () => canvas.insert_field (ff));
                }
                if (doc.pub.merge.active ()) {
                    var mf = menu.add_submenu (_("Insert Merge Field"), null);
                    foreach (string f in doc.pub.merge.fields) {
                        string ff = f;
                        mf.add_item (f, null, () => canvas.insert_field (Fields.merge (ff)));
                    }
                }
                menu.add_item (_("Edit in Story Editor"), "accessories-text-editor-symbolic", () => run ("story-editor"));
                popup_menu (menu);
                return;
            }
            if (sel ().size > 0) {
                menu.add_item (_("Cut"), "edit-cut-symbolic", () => run ("cut"));
                menu.add_item (_("Copy"), "edit-copy-symbolic", () => run ("copy"));
                menu.add_item (_("Paste"), "edit-paste-symbolic", () => run ("paste"));
                menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => run ("duplicate"));
                menu.add_separator ();
                var arr = menu.add_submenu (_("Arrange"), null);
                arr.add_item (_("Bring to Front"), null, () => run ("bring-front"));
                arr.add_item (_("Bring Forward"), null, () => run ("bring-forward"));
                arr.add_item (_("Send Backward"), null, () => run ("send-backward"));
                arr.add_item (_("Send to Back"), null, () => run ("send-back"));
                var wrapm = menu.add_submenu (_("Text Wrap"), null);
                string[,] wraps = { { _("No Text Wrap"), "none" }, { _("Wrap Around Bounding Box"), "box" }, { _("Wrap Around Object Shape"), "contour" }, { _("Jump Object"), "jump" } };
                for (int i = 0; i < wraps.length[0]; i++) {
                    string v = wraps[i, 1];
                    wrapm.add_item (wraps[i, 0], null, () => activate_action_variant ("win.wrap", new Variant.string (v)));
                }
                if (single_image () != null) {
                    var fitm = menu.add_submenu (_("Fitting"), null);
                    fitm.add_item (_("Fill Frame Proportionally"), null, () => run ("fit-fill"));
                    fitm.add_item (_("Fit Content Proportionally"), null, () => run ("fit-content"));
                    fitm.add_item (_("Fit Content to Frame"), null, () => run ("fit-stretch"));
                    fitm.add_item (_("Center Content"), null, () => run ("fit-center"));
                    fitm.add_item (_("Fit Frame to Content"), null, () => run ("fit-frame-content"));
                    menu.add_item (_("Place Picture…"), "insert-image-symbolic", () => run ("place"));
                    menu.add_item (_("Relink…"), "insert-link-symbolic", () => run ("relink"));
                }
                if (single_text_frame () != null) {
                    menu.add_item (_("Thread to New Frame"), null, () => run ("thread-new"));
                    menu.add_item (_("Unthread After This Frame"), null, () => run ("unthread"));
                    menu.add_item (_("Fit Frame to Text"), null, () => run ("fit-frame"));
                    menu.add_item (_("Edit in Story Editor"), "accessories-text-editor-symbolic", () => run ("story-editor"));
                }
                if (sel ().size == 1 && sel ()[0] is TableItem) {
                    var tm = menu.add_submenu (_("Table"), null);
                    tm.add_item (_("Insert Row Above"), null, () => run ("table-row-above"));
                    tm.add_item (_("Insert Row Below"), null, () => run ("table-row-below"));
                    tm.add_item (_("Delete Row"), null, () => run ("table-row-delete"));
                    tm.add_item (_("Insert Column Left"), null, () => run ("table-col-left"));
                    tm.add_item (_("Insert Column Right"), null, () => run ("table-col-right"));
                    tm.add_item (_("Delete Column"), null, () => run ("table-col-delete"));
                    tm.add_item (_("Merge Cells"), null, () => run ("table-merge"));
                    tm.add_item (_("Split Cell"), null, () => run ("table-split"));
                    tm.add_item (_("Distribute Rows and Columns"), null, () => run ("table-distribute"));
                }
                if (sel ().size > 1) menu.add_item (_("Group"), null, () => run ("group"));
                if (sel ().size == 1 && sel ()[0] is GroupItem) menu.add_item (_("Ungroup"), null, () => run ("ungroup"));
                menu.add_item (sel ()[0].locked ? _("Unlock") : _("Lock"), "changes-prevent-symbolic", () => run ("lock"));
                menu.add_separator ();
                menu.add_item (_("Delete"), "user-trash-symbolic", () => run ("delete"), "destructive-action");
            } else {
                menu.add_item (_("Paste"), "edit-paste-symbolic", () => run ("paste"));
                menu.add_item (_("Place Picture…"), "insert-image-symbolic", () => run ("place"));
                menu.add_separator ();
                menu.add_item (_("Add Page"), "document-new-symbolic", () => run ("add-page"));
                menu.add_item (_("Override All Master Items"), null, () => run ("override-master"));
                menu.add_item (_("Create Guides…"), null, () => run ("create-guides"));
                menu.add_item (_("Document Setup…"), "document-properties-symbolic", () => run ("document-setup"));
            }
            popup_menu (menu);
        }
    }
}
