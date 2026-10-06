using Gtk;

namespace Singularity.Apps.Publish {

    public class PublishApp : Singularity.Application {
        public GLib.Settings? settings = null;
        private Singularity.DockMenu? dock_menu = null;

        public PublishApp () {
            Object (application_id: "dev.sinty.publish", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new", 0, OptionFlags.NONE, OptionArg.NONE, _("Start a new publication"), null);
            add_main_option ("templates", 0, OptionFlags.NONE, OptionArg.NONE, _("Choose a template for a new publication"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            string? action = null;
            if (options.contains ("new")) action = "new";
            else if (options.contains ("templates")) action = "new-from-template";
            if (action == null) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("publish: %s", e.message);
                return 1;
            }
            activate_action (action, null);
            return get_is_remote () ? 0 : -1;
        }

        public string get_string (string key, string fallback) {
            if (settings == null) return fallback;
            return settings.get_string (key);
        }

        public bool get_bool (string key, bool fallback) {
            if (settings == null) return fallback;
            return settings.get_boolean (key);
        }

        public int get_int (string key, int fallback) {
            if (settings == null) return fallback;
            return settings.get_int (key);
        }

        public void set_bool (string key, bool v) {
            if (settings != null) settings.set_boolean (key, v);
        }

        private PublishWindow target_window () {
            var w = get_active_window () as PublishWindow;
            if (w == null) {
                w = new PublishWindow (this);
                w.present ();
            }
            return w;
        }

        protected override void startup () {
            base.startup ();
            var source = SettingsSchemaSource.get_default ();
            if (source != null && source.lookup ("dev.sinty.publish", true) != null) settings = new GLib.Settings ("dev.sinty.publish");
            about_description = _("Lay out flyers, brochures, newsletters and cards for print");
            IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/publish/icons");
            Singularity.Application.add_app_css (CSS);
            Singularity.Text.SpellIntegration.install (this);

            var new_action = new SimpleAction ("new", null);
            new_action.activate.connect (() => {
                var w = get_active_window () as PublishWindow;
                if (w == null) {
                    w = new PublishWindow (this);
                    w.present ();
                }
                Dialogs.new_document (w);
            });
            add_action (new_action);
            var template_action = new SimpleAction ("new-from-template", null);
            template_action.activate.connect (() => Dialogs.templates (target_window ()));
            add_action (template_action);
            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (() => choose_file (target_window ()));
            add_action (open_action);
            var open_online = new SimpleAction ("open-online", null);
            open_online.activate.connect (() => {
                var w = target_window ();
                CloudActions.open.begin (w, (f) => open_file (f, w));
            });
            add_action (open_online);
            var open_files = new SimpleAction ("open-files", new VariantType ("as"));
            open_files.activate.connect ((param) => {
                foreach (string uri in param.get_strv ()) open_file (File.new_for_uri (uri), null);
            });
            add_action (open_files);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.publish");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            build_menu ();
            string[,] accels = {
                { "app.quit", "<Control>q" }, { "app.new", "<Control>n" }, { "app.open", "<Control>o" },
                { "app.new-from-template", "<Control><Shift>n" }, { "app.settings", "<Control>comma" },
                { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" }, { "win.print", "<Control>p" },
                { "win.place", "<Control>d" }, { "win.export-pdf", "<Control>e" }, { "win.export-images", "<Control><Alt>e" },
                { "win.document-setup", "<Control><Alt>p" }, { "win.close-doc", "<Control>w" }, { "win.close", "<Control><Shift>w" },
                { "win.undo", "<Control>z" }, { "win.cut", "<Control>x" }, { "win.copy", "<Control>c" }, { "win.paste", "<Control>v" },
                { "win.paste-in-place", "<Control><Alt><Shift>v" }, { "win.duplicate", "<Control><Alt><Shift>d" }, { "win.step-repeat", "<Control><Alt>u" },
                { "win.select-all", "<Control>a" }, { "win.deselect", "<Control><Shift>a" },
                { "win.find", "<Control>f" }, { "win.spelling", "<Control>i" }, { "win.story-editor", "<Control>y" },
                { "win.preflight", "<Control><Alt><Shift>f" }, { "win.package", "<Control><Alt><Shift>p" },
                { "win.bold", "<Control>b" }, { "win.italic", "<Control><Shift>i" }, { "win.underline", "<Control>u" },
                { "win.strike", "<Control><Shift>slash" }, { "win.superscript", "<Control><Shift>equal" }, { "win.subscript", "<Control><Alt><Shift>equal" },
                { "win.all-caps", "<Control><Shift>k" }, { "win.small-caps", "<Control><Shift>h" },
                { "win.align-left", "<Control><Shift>l" }, { "win.align-center", "<Control><Shift>c" }, { "win.align-right", "<Control><Shift>r" },
                { "win.align-justify", "<Control><Shift>j" }, { "win.align-justify-all", "<Control><Shift>f" },
                { "win.font-bigger", "<Control><Shift>greater" }, { "win.font-smaller", "<Control><Shift>less" },
                { "win.frame-options", "<Control><Alt>b" }, { "win.fit-frame", "<Control><Alt>c" },
                { "win.insert-page-number", "<Control><Alt><Shift>n" }, { "win.insert-next-page", "<Control><Alt><Shift>bracketright" }, { "win.insert-prev-page", "<Control><Alt><Shift>bracketleft" },
                { "win.group", "<Control>g" }, { "win.ungroup", "<Control><Shift>g" }, { "win.lock", "<Control>l" }, { "win.unlock-all", "<Control><Alt>l" },
                { "win.hide", "<Control>3" }, { "win.show-all", "<Control><Alt>3" },
                { "win.bring-front", "<Control><Shift>bracketright" }, { "win.bring-forward", "<Control>bracketright" },
                { "win.send-backward", "<Control>bracketleft" }, { "win.send-back", "<Control><Shift>bracketleft" },
                { "win.fit-fill", "<Control><Alt><Shift>c" }, { "win.fit-content", "<Control><Alt><Shift>e" },
                { "win.add-page", "<Control><Shift>p" }, { "win.go-to-page", "<Control>j" },
                { "win.first-page", "<Control><Shift>Page_Up" }, { "win.last-page", "<Control><Shift>Page_Down" },
                { "win.show-rulers", "<Control>r" }, { "win.show-guides", "<Control>semicolon" }, { "win.snap-guides", "<Control><Shift>semicolon" },
                { "win.smart-guides", "<Control>u" }, { "win.show-baseline", "<Control><Alt>apostrophe" }, { "win.frame-edges", "<Control>h" },
                { "win.preview-mode", "<Control><Alt>w" },
                { "win.panel-pages", "F12" }, { "win.panel-format", "<Control>F9" }, { "win.panel-styles", "F11" }, { "win.panel-swatches", "F5" },
                { "win.panel-layers", "F7" }, { "win.panel-links", "<Control><Shift>d" }, { "win.panel-merge", "<Control><Alt>m" },
                { "win.zoom-fit", "<Control>0" }, { "win.zoom-actual", "<Control>1" }, { "win.zoom-spread", "<Control><Alt>0" },
                { "win.merge-preview", "<Control><Alt>r" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.smart-guides", {});
            set_accels_for_action ("win.panel-pages", { "F9", "F12" });
            set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            set_accels_for_action ("win.story-editor", { "<Control><Alt>y" });
            set_accels_for_action ("win.zoom-in", { "<Control>plus", "<Control>equal" });
            set_accels_for_action ("win.zoom-out", { "<Control>minus" });
            setup_dock_menu ();
        }

        private void setup_dock_menu () {
            dock_menu = new Singularity.DockMenu ("dev.sinty.publish");
            dock_menu.add_item ("new", _("New Publication"), "document-new-symbolic");
            dock_menu.add_item ("templates", _("New from Template"), "x-office-document-template-symbolic");
            dock_menu.activated.connect ((id) => {
                if (id == "new") activate_action ("new", null);
                else if (id == "templates") activate_action ("new-from-template", null);
            });
            dock_menu.publish ();
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        private static GLib.Menu submenu_section (string label, GLib.Menu sub) {
            var m = new GLib.Menu ();
            m.append_submenu (label, sub);
            return m;
        }

        private static GLib.Menu targeted (string action, string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) {
                var it = new GLib.MenuItem (items[i, 0], null);
                it.set_action_and_target_value (action, new Variant.string (items[i, 1]));
                m.append_item (it);
            }
            return m;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();

            var file = new GLib.Menu ();
            file.append_section (null, section ({ { _("New…"), "app.new" }, { _("New from Template…"), "app.new-from-template" }, { _("Open…"), "app.open" }, { _("Open from Online Account…"), "app.open-online" } }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" }, { _("Save to Online Account…"), "win.save-online" } }));
            file.append_section (null, section ({ { _("Print…"), "win.print" } }));
            var export = section ({ { _("PDF for Print…"), "win.export-pdf" }, { _("Images (PNG, JPEG, TIFF, GIF, BMP)…"), "win.export-images" }, { _("Web Page (HTML)…"), "win.export-html" }, { _("Web Site…"), "win.export-site" }, { _("EPUB, Reflowable…"), "win.export-epub" }, { _("EPUB, Fixed Layout…"), "win.export-epub-fixed" }, { _("XPS Document…"), "win.export-xps" }, { _("Word Document (DOCX)…"), "win.export-docx" }, { _("OpenDocument Drawing (ODG)…"), "win.export-odg" }, { _("InDesign Markup (IDML)…"), "win.export-idml" }, { _("Scribus Document…"), "win.export-sla" } });
            var export_section = submenu_section (_("Export"), export);
            export_section.append (_("Package for a Printer…"), "win.package");
            export_section.append (_("Book…"), "win.book");
            file.append_section (null, export_section);
            file.append_section (null, section ({ { _("Share…"), "win.share" }, { _("Send as Email…"), "win.send-email" } }));
            file.append_section (null, section ({ { _("Place…"), "win.place" }, { _("Place Spreadsheet as Linked Table…"), "win.place-spreadsheet" }, { _("Import XML…"), "win.import-xml" }, { _("Insert Text File…"), "win.insert-text-file" } }));
            file.append_section (null, section ({ { _("Document Setup…"), "win.document-setup" }, { _("Create Alternate Layout…"), "win.alternate-layout" }, { _("Update Alternate Layouts"), "win.update-alternate-layouts" }, { _("Business Information…"), "win.business-information" }, { _("Properties…"), "win.properties" } }));
            file.append_section (null, section ({ { _("Close Publication"), "win.close-doc" } }));
            file.append_section (null, section ({ { _("Close Window"), "win.close" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);

            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Cut"), "win.cut" }, { _("Copy"), "win.copy" }, { _("Paste"), "win.paste" }, { _("Paste in Place"), "win.paste-in-place" }, { _("Duplicate"), "win.duplicate" }, { _("Step and Repeat…"), "win.step-repeat" }, { _("Delete"), "win.delete" } }));
            edit.append_section (null, section ({ { _("Select All"), "win.select-all" }, { _("Deselect All"), "win.deselect" } }));
            edit.append_section (null, section ({ { _("Find and Replace…"), "win.find" }, { _("Find and Change…"), "win.find-advanced" }, { _("Check Spelling…"), "win.spelling" }, { _("Thesaurus…"), "win.thesaurus" }, { _("Edit in Story Editor"), "win.story-editor" } }));
            edit.append_section (null, section ({ { _("Settings"), "app.settings" } }));
            menu.append_submenu (_("Edit"), edit);

            var view = new GLib.Menu ();
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Fit Page in Window"), "win.zoom-fit" }, { _("Fit Spread in Window"), "win.zoom-spread" }, { _("Actual Size"), "win.zoom-actual" } }));
            view.append_section (null, section ({ { _("Preview Mode"), "win.preview-mode" }, { _("Rulers"), "win.show-rulers" }, { _("Guides"), "win.show-guides" }, { _("Snap to Guides"), "win.snap-guides" }, { _("Smart Guides"), "win.smart-guides" }, { _("Baseline Grid"), "win.show-baseline" }, { _("Frame Edges"), "win.frame-edges" }, { _("Hidden Characters"), "win.hidden-chars" } }));
            view.append_section (null, section ({ { _("Pages"), "win.panel-pages" }, { _("Format"), "win.panel-format" }, { _("Styles"), "win.panel-styles" }, { _("Swatches"), "win.panel-swatches" }, { _("Layers"), "win.panel-layers" }, { _("Links"), "win.panel-links" }, { _("Preflight"), "win.panel-preflight" }, { _("Separations Preview"), "win.panel-separations" }, { _("Review"), "win.panel-review" }, { _("Suite Library"), "win.panel-library" }, { _("Mail Merge"), "win.panel-merge" } }));
            menu.append_submenu (_("View"), view);

            var insert = new GLib.Menu ();
            insert.append_section (null, section ({ { _("Text Frame"), "win.insert-text" }, { _("Image Frame"), "win.insert-image-frame" }, { _("Picture…"), "win.place" }, { _("Table…"), "win.insert-table" }, { _("WordArt…"), "win.insert-wordart" }, { _("Building Blocks…"), "win.insert-building-block" } }));
            var shapes = targeted ("win.insert-shape", { { _("Rectangle"), "rect" }, { _("Ellipse"), "ellipse" }, { _("Polygon"), "polygon" }, { _("Star"), "star" }, { _("Line"), "line" } });
            var more_shapes = new GLib.Menu ();
            foreach (string cat in ShapeLib.categories ()) {
                var cm = new GLib.Menu ();
                foreach (var p in ShapeLib.all ()) {
                    if (p.category != cat) continue;
                    var it = new GLib.MenuItem (p.name, null);
                    it.set_action_and_target_value ("win.insert-preset", new Variant.string (p.id));
                    cm.append_item (it);
                }
                more_shapes.append_submenu (cat, cm);
            }
            var shape_section = submenu_section (_("Shapes"), shapes);
            shape_section.append_submenu (_("More Shapes"), more_shapes);
            shape_section.append (_("Freeform Drawing"), "win.tool-freeform");
            shape_section.append (_("Pen (Click Points)"), "win.tool-pen");
            insert.append_section (null, shape_section);
            insert.append_section (null, section ({ { _("Text File…"), "win.insert-text-file" }, { _("Symbol…"), "win.insert-symbol" }, { _("Hyperlink…"), "win.insert-hyperlink" }, { _("Bookmark…"), "win.insert-bookmark" }, { _("Text Variable…"), "win.text-variables" } }));
            var fields = section ({ { _("Page Number"), "win.insert-page-number" }, { _("Page Count"), "win.insert-page-count" }, { _("Section Name"), "win.insert-section" }, { _("Next Page Number"), "win.insert-next-page" }, { _("Previous Page Number"), "win.insert-prev-page" }, { _("Date"), "win.insert-date" }, { _("Time"), "win.insert-time" }, { _("Document Title"), "win.insert-title" } });
            var fields_section = submenu_section (_("Field"), fields);
            var biz = new GLib.Menu ();
            foreach (string k in BusinessInfo.KEYS) {
                if (k == "logo") continue;
                var it = new GLib.MenuItem (BusinessInfo.label (k), null);
                it.set_action_and_target_value ("win.insert-business-field", new Variant.string (k));
                biz.append_item (it);
            }
            fields_section.append_submenu (_("Business Information"), biz);
            insert.append_section (null, fields_section);
            var chars = targeted ("win.insert-char", { { _("Discretionary Hyphen"), "shy" }, { _("Nonbreaking Space"), "nbsp" }, { _("Em Space"), "emsp" }, { _("En Space"), "ensp" }, { _("Forced Line Break"), "lsep" }, { _("Tab"), "tab" }, { _("Bullet"), "bullet" }, { _("Copyright Symbol"), "copy" }, { _("Registered Symbol"), "reg" }, { _("Trademark Symbol"), "tm" } });
            insert.append_section (null, submenu_section (_("Special Character"), chars));
            menu.append_submenu (_("Insert"), insert);

            var design = new GLib.Menu ();
            design.append_section (null, section ({ { _("Colour Schemes…"), "win.color-schemes" }, { _("Font Schemes…"), "win.font-schemes" }, { _("Business Information…"), "win.business-information" } }));
            design.append_section (null, section ({ { _("Building Blocks…"), "win.insert-building-block" }, { _("Save Selection as Building Block…"), "win.save-building-block" } }));
            design.append_section (null, section ({ { _("Design Checker"), "win.design-checker" }, { _("Commercial Print Checker"), "win.commercial-checker" }, { _("Accessibility Checker"), "win.accessibility-checker" } }));
            design.append_section (null, section ({ { _("Convert RGB Swatches to CMYK"), "win.convert-rgb-swatches" } }));
            menu.append_submenu (_("Page Design"), design);

            var text = new GLib.Menu ();
            text.append_section (null, section ({ { _("Bold"), "win.bold" }, { _("Italic"), "win.italic" }, { _("Underline"), "win.underline" }, { _("Strikethrough"), "win.strike" }, { _("Superscript"), "win.superscript" }, { _("Subscript"), "win.subscript" }, { _("All Caps"), "win.all-caps" }, { _("Small Caps"), "win.small-caps" }, { _("Larger"), "win.font-bigger" }, { _("Smaller"), "win.font-smaller" } }));
            text.append_section (null, section ({ { _("Align Left"), "win.align-left" }, { _("Align Center"), "win.align-center" }, { _("Align Right"), "win.align-right" }, { _("Justify"), "win.align-justify" }, { _("Justify All Lines"), "win.align-justify-all" } }));
            text.append_section (null, section ({ { _("Bulleted List"), "win.bullets" }, { _("Numbered List"), "win.numbering" }, { _("Drop Cap"), "win.drop-cap" }, { _("Hyphenate"), "win.hyphenate" }, { _("Align to Baseline Grid"), "win.align-grid" }, { _("Clear Overrides"), "win.clear-overrides" } }));
            text.append_section (null, section ({ { _("Nested and GREP Styles…"), "win.style-rules" }, { _("Justification…"), "win.justification" }, { _("Hyphenation…"), "win.hyphenation-settings" }, { _("Hyphenation Exceptions…"), "win.hyphenation-exceptions" } }));
            text.append_section (null, section ({ { _("Paragraph and Character Styles"), "win.panel-styles" }, { _("Import Styles…"), "win.import-styles" }, { _("Text Frame Options…"), "win.frame-options" }, { _("Fit Frame to Text"), "win.fit-frame" } }));
            var fitm = targeted ("win.autofit", { { _("Do Not Autofit"), "0" }, { _("Shrink Text on Overflow"), "1" }, { _("Best Fit"), "2" }, { _("Grow Frame to Fit Text"), "grow" } });
            var fit_section = submenu_section (_("Text Fit"), fitm);
            fit_section.append (_("Autoflow Overset Text"), "win.autoflow");
            fit_section.append (_("Rotate Text 90°"), "win.text-direction");
            text.append_section (null, fit_section);
            text.append_section (null, section ({ { _("Thread to New Frame"), "win.thread-new" }, { _("Unthread After This Frame"), "win.unthread" }, { _("Remove Frame from Thread"), "win.detach-frame" } }));
            text.append_section (null, section ({ { _("Anchored Object Options…"), "win.anchored-options" } }));
            text.append_section (null, section ({ { _("Insert Footnote"), "win.insert-footnote" }, { _("Edit Footnote…"), "win.edit-footnote" }, { _("Footnote Options…"), "win.footnote-options" } }));
            text.append_section (null, section ({ { _("Export Story for Writing…"), "win.export-story" }, { _("Insert Endnote"), "win.insert-endnote" }, { _("Update Endnotes"), "win.update-endnotes" } }));
            text.append_section (null, section ({ { _("Insert Cross-Reference…"), "win.insert-cross-reference" }, { _("Text Anchor…"), "win.text-anchor" } }));
            text.append_section (null, section ({ { _("Conditional Text…"), "win.conditions" }, { _("New Index Entry…"), "win.index-entry" }, { _("Generate Index…"), "win.generate-index" } }));
            text.append_section (null, section ({ { _("Hyperlink…"), "win.insert-hyperlink" }, { _("Remove Hyperlink"), "win.remove-hyperlink" }, { _("Bookmarks…"), "win.bookmarks" } }));
            menu.append_submenu (_("Text"), text);

            var obj = new GLib.Menu ();
            obj.append_section (null, submenu_section (_("Pathfinder"), section ({ { _("Unite"), "win.pathfinder-unite" }, { _("Subtract Front from Back"), "win.pathfinder-subtract" }, { _("Intersect"), "win.pathfinder-intersect" }, { _("Exclude Overlap"), "win.pathfinder-exclude" }, { _("Convert to Path"), "win.convert-to-path" } })));
            obj.append_section (null, submenu_section (_("Arrange"), section ({ { _("Bring to Front"), "win.bring-front" }, { _("Bring Forward"), "win.bring-forward" }, { _("Send Backward"), "win.send-backward" }, { _("Send to Back"), "win.send-back" } })));
            var aligns = section ({ { _("Left Edges"), "win.arrange-left" }, { _("Horizontal Centers"), "win.arrange-center" }, { _("Right Edges"), "win.arrange-right" }, { _("Top Edges"), "win.arrange-top" }, { _("Vertical Centers"), "win.arrange-middle" }, { _("Bottom Edges"), "win.arrange-bottom" } });
            var align_to = targeted ("win.align-to", { { _("Selection"), "selection" }, { _("Margins"), "margins" }, { _("Page"), "page" }, { _("Spread"), "spread" } });
            var al = submenu_section (_("Align"), aligns);
            al.append_submenu (_("Distribute"), section ({ { _("Horizontally"), "win.distribute-h" }, { _("Vertically"), "win.distribute-v" } }));
            al.append_submenu (_("Align To"), align_to);
            obj.append_section (null, al);
            obj.append_section (null, section ({ { _("Group"), "win.group" }, { _("Ungroup"), "win.ungroup" }, { _("Lock"), "win.lock" }, { _("Unlock All on Page"), "win.unlock-all" }, { _("Hide"), "win.hide" }, { _("Show All on Page"), "win.show-all" } }));
            var wrap = targeted ("win.wrap", { { _("No Text Wrap"), "none" }, { _("Square"), "box" }, { _("Tight"), "contour" }, { _("Through"), "through" }, { _("Top and Bottom"), "jump" }, { _("Behind Text"), "behind" }, { _("In Front of Text"), "front" } });
            wrap.append (_("Edit Wrap Points"), "win.edit-wrap-points");
            wrap.append (_("Reset Wrap Points"), "win.reset-wrap-points");
            var fit = section ({ { _("Fill Frame Proportionally"), "win.fit-fill" }, { _("Fit Content Proportionally"), "win.fit-content" }, { _("Fit Content to Frame"), "win.fit-stretch" }, { _("Center Content"), "win.fit-center" }, { _("Fit Frame to Content"), "win.fit-frame-content" } });
            var sub = submenu_section (_("Text Wrap"), wrap);
            sub.append_submenu (_("Fitting"), fit);
            sub.append_submenu (_("Transform"), section ({ { _("Flip Horizontal"), "win.flip-h" }, { _("Flip Vertical"), "win.flip-v" }, { _("Rotate 90° Clockwise"), "win.rotate-cw" }, { _("Rotate 90° Counterclockwise"), "win.rotate-ccw" } }));
            obj.append_section (null, sub);
            var pic_styles = new GLib.Menu ();
            foreach (string id in PictureStyles.ids ()) {
                var it = new GLib.MenuItem (PictureStyles.label (id), null);
                it.set_action_and_target_value ("win.picture-style", new Variant.string (id));
                pic_styles.append_item (it);
            }
            var crop = new GLib.Menu ();
            foreach (string id in ShapeLib.clip_shapes ()) {
                var it = new GLib.MenuItem (ShapeLib.clip_label (id), null);
                it.set_action_and_target_value ("win.crop-to-shape", new Variant.string (id));
                crop.append_item (it);
            }
            var caps = new GLib.Menu ();
            foreach (string id in Captions.ids ()) {
                var it = new GLib.MenuItem (Captions.label (id), null);
                it.set_action_and_target_value ("win.add-caption", new Variant.string (id));
                caps.append_item (it);
            }
            var pic = submenu_section (_("Picture Styles"), pic_styles);
            pic.append_submenu (_("Crop to Shape"), crop);
            pic.append_submenu (_("Caption"), caps);
            pic.append (_("Swap Pictures"), "win.swap-pictures");
            pic.append (_("Reset Picture"), "win.reset-picture");
            pic.append (_("Alternative Text…"), "win.alt-text");
            obj.append_section (null, pic);
            var tables = new GLib.Menu ();
            foreach (string id in TableFormats.ids ()) {
                var it = new GLib.MenuItem (TableFormats.label (id), null);
                it.set_action_and_target_value ("win.table-format", new Variant.string (id));
                tables.append_item (it);
            }
            var tsec = submenu_section (_("Table Format"), tables);
            tsec.append (_("Continue Table in Another Frame"), "win.table-continue");
            tsec.append (_("Table Header and Flow…"), "win.table-flow-options");
            tsec.append_submenu (_("Diagonals"), targeted ("win.cell-diagonal", { { _("No Diagonal"), "0" }, { _("Divide Down"), "1" }, { _("Divide Up"), "2" } }));
            tsec.append (_("BorderArt…"), "win.border-art");
            obj.append_section (null, tsec);
            obj.append_section (null, section ({ { _("Relink…"), "win.relink" }, { _("Embed Image"), "win.embed" }, { _("Override Master Items"), "win.override-master" }, { _("Nonprinting"), "win.nonprinting" } }));
            menu.append_submenu (_("Object"), obj);

            var layout = new GLib.Menu ();
            layout.append_section (null, section ({ { _("Add Page"), "win.add-page" }, { _("Insert Pages…"), "win.insert-pages" }, { _("Duplicate Page"), "win.duplicate-page" }, { _("Delete Page"), "win.delete-page" }, { _("Move Page Up"), "win.page-up" }, { _("Move Page Down"), "win.page-down" } }));
            layout.append_section (null, section ({ { _("New Master Page"), "win.new-master" }, { _("Edit Master Pages"), "win.edit-masters" }, { _("Numbering and Section Options…"), "win.sections" } }));
            layout.append_section (null, section ({ { _("Margins and Columns…"), "win.document-setup" }, { _("Create Guides…"), "win.create-guides" }, { _("Clear Guides on Page"), "win.clear-guides" } }));
            layout.append_section (null, section ({ { _("Table of Contents…"), "win.toc" }, { _("Update Table of Contents"), "win.toc-update" } }));
            layout.append_section (null, section ({ { _("First Page"), "win.first-page" }, { _("Previous Page"), "win.prev-page" }, { _("Next Page"), "win.next-page" }, { _("Last Page"), "win.last-page" }, { _("Go to Page…"), "win.go-to-page" } }));
            menu.append_submenu (_("Layout"), layout);

            var mail = new GLib.Menu ();
            mail.append_section (null, section ({ { _("Use a CSV File…"), "win.merge-csv" }, { _("Use a Spreadsheet…"), "win.merge-sheet" }, { _("Use a Database…"), "win.merge-database" }, { _("Use Contacts"), "win.merge-contacts" }, { _("Type a New List…"), "win.merge-new-list" }, { _("Remove Data Source"), "win.merge-remove" } }));
            mail.append_section (null, section ({ { _("Edit Recipient List…"), "win.merge-recipients" } }));
            mail.append_section (null, section ({ { _("Preview Results"), "win.merge-preview" }, { _("First Record"), "win.merge-first" }, { _("Previous Record"), "win.merge-prev" }, { _("Next Record"), "win.merge-next" }, { _("Last Record"), "win.merge-last" } }));
            mail.append_section (null, section ({ { _("Catalogue Merge"), "win.merge-catalogue" }, { _("Set Catalogue Area from Selection"), "win.merge-area" } }));
            mail.append_section (null, section ({ { _("Merge to PDF…"), "win.merge-pdf" }, { _("Merge to New Publication"), "win.merge-new" }, { _("Print Merged…"), "win.merge-print" }, { _("Merge to Email…"), "win.merge-email" } }));
            menu.append_submenu (_("Mailings"), mail);

            var tools = new GLib.Menu ();
            tools.append_section (null, section ({ { _("Macros…"), "win.macros" }, { _("Record Macro"), "win.macro-record" } }));
            tools.append_section (null, section ({ { _("Check Spelling…"), "win.spelling" }, { _("Thesaurus…"), "win.thesaurus" }, { _("Accessibility Checker"), "win.accessibility-checker" } }));
            menu.append_submenu (_("Tools"), tools);

            set_menubar (menu);
        }

        public override void activate () {
            var w = get_active_window ();
            if (w == null) w = new PublishWindow (this);
            w.present ();
        }

        public override void open (File[] files, string hint) {
            foreach (var f in files) open_file (f, null);
        }

        public void open_file (File file, PublishWindow? target) {
            string? path = file.get_path ();
            if (path == null) return;
            foreach (var w in get_windows ()) {
                var pw = w as PublishWindow;
                if (pw != null && pw.doc != null && pw.doc.path == path) {
                    pw.present ();
                    return;
                }
            }
            PublishWindow? win = target != null && target.is_empty () ? target : null;
            if (win == null) {
                foreach (var w in get_windows ()) {
                    var pw = w as PublishWindow;
                    if (pw != null && pw.is_empty ()) win = pw;
                }
            }
            if (win == null) win = new PublishWindow (this);
            win.present ();
            if (path.has_suffix ("." + Book.EXTENSION)) {
                BookDialog.open_path (win, path);
                return;
            }
            try {
                var d = Document.open (path);
                win.load_document (d);
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (file.get_uri ());
            } catch (Error e) {
                win.show_error (_("Could Not Open"), _("\"%s\" could not be opened: %s").printf (file.get_basename (), e.message));
            }
        }

        public static string[] open_suffixes () {
            return { NativeFormat.EXT, "sla", "sla.gz", "idml", "pub", "indd", LinkedStory.EXT };
        }

        public void choose_file (PublishWindow parent) {
            var dialog = new FileDialog ();
            dialog.title = _("Open Publication");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var all = new FileFilter ();
            all.name = _("Publications");
            foreach (string s in open_suffixes ()) all.add_suffix (s);
            filters.append (all);
            string[,] kinds = { { _("Publish Documents"), NativeFormat.EXT }, { _("Scribus Documents"), "sla" }, { _("InDesign Markup (IDML)"), "idml" }, { _("Publisher Files"), "pub" }, { _("InDesign Documents (Preview Only)"), "indd" } };
            for (int i = 0; i < kinds.length[0]; i++) {
                var f = new FileFilter ();
                f.name = kinds[i, 0];
                f.add_suffix (kinds[i, 1]);
                filters.append (f);
            }
            dialog.filters = filters;
            dialog.default_filter = all;
            dialog.open.begin (parent, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) open_file (file, parent);
                } catch (Error e) {
                }
            });
        }

        private const string CSS = """
.publish-stage {
    border-radius: 12px;
    margin: 0 12px 12px 12px;
}

.sx-inspector {
    border-left: 1px solid alpha(@window_fg_color, 0.08);
}

.sx-inspector-header {
    margin: 0 14px 10px 14px;
}

.sx-layer-list {
    background: transparent;
}

.sx-layer-list row {
    padding: 0;
    margin: 0 0 1px 0;
    border-radius: 8px;
    min-height: 0;
}

.sx-layer-list row:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

.sx-layer-list row.sx-layer-active {
    background-color: alpha(@accent_bg_color, 0.12);
}

.sx-layer-list row.sx-layer-selected {
    background-color: alpha(@accent_bg_color, 0.22);
}

.sx-layer-list row.sx-drop-before {
    box-shadow: inset 0 2px 0 @accent_bg_color;
}

.sx-layer-list row.sx-drop-after {
    box-shadow: inset 0 -2px 0 @accent_bg_color;
}

.sx-layer-list row.sx-drop-into {
    box-shadow: inset 0 0 0 2px @accent_bg_color;
}

.sx-layer-toggle {
    min-width: 24px;
    min-height: 24px;
    padding: 0;
    border-radius: 6px;
}

.sx-layer-toggle.sx-off {
    opacity: 0.45;
}

.sx-layer-thumb {
    border-radius: 4px;
    background-color: @view_bg_color;
    box-shadow: 0 0 0 1px alpha(@window_fg_color, 0.12);
}

.sx-layer-name.sx-layer-is-layer {
    font-weight: 600;
}

.sx-layer-edit {
    min-height: 0;
    padding: 2px 6px;
}

.sx-layer-list-bar {
    padding-top: 8px;
    border-top: 1px solid alpha(@window_fg_color, 0.08);
}

.publish-panel {
    padding: 2px 14px 24px 14px;
}

.publish-page-thumb {
    border-radius: 3px;
    box-shadow: 0 1px 3px alpha(black, 0.28);
}

.publish-page-cell {
    border-radius: 10px;
    padding: 6px;
}

.publish-page-cell.current {
    background-color: alpha(@accent_color, 0.16);
}

.publish-page-cell.current .publish-page-thumb {
    box-shadow: 0 0 0 2px @accent_color;
}

.publish-page-label {
    font-feature-settings: "tnum";
    font-size: 12px;
}

.publish-template-card {
    border-radius: 12px;
    padding: 6px;
}

.publish-template-thumb {
    border-radius: 4px;
    box-shadow: 0 1px 4px alpha(black, 0.3);
}

.publish-recent-row {
    border-radius: 10px;
    padding: 8px 10px;
}

.publish-swatch {
    min-width: 22px;
    min-height: 22px;
    padding: 0;
    border-radius: 6px;
    box-shadow: inset 0 0 0 1px alpha(@window_fg_color, 0.2);
}

.publish-issue-row {
    border-radius: 10px;
    padding: 6px 8px;
}

.publish-story-editor textview,
.publish-story-editor textview text {
    font-family: monospace;
}

.publish-style-gutter {
    font-size: 11px;
}
""";
    }
}
