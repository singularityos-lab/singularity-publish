using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Publish {

    public class PreflightProfiles {
        private static SpinRow spin (PreferencesGroup g, string title, double min, double max, double step, double value, int digits = 0) {
            var r = new SpinRow (title, null, min, max, step, value);
            r.spin_btn.digits = digits;
            g.add_row (r);
            return r;
        }

        public static string summary (PreflightProfile p) {
            string[] parts = {};
            if (p.links) parts += _("links");
            if (p.images) parts += _("pictures below %d ppi").printf ((int) p.min_ppi);
            if (p.images && p.max_ppi > 0) parts += _("pictures above %d ppi").printf ((int) p.max_ppi);
            if (p.text) parts += _("overset text");
            if (p.fonts) parts += _("missing fonts");
            if (p.min_text > 0) parts += _("text below %s pt").printf ("%g".printf (p.min_text));
            if (p.color && !p.allow_rgb) parts += _("RGB in a CMYK job");
            if (p.color && !p.allow_spot) parts += _("spot colours");
            if (p.color && p.ink_limit > 0) parts += _("total ink over %d%%").printf ((int) p.ink_limit);
            if (p.transparency) parts += _("transparency");
            if (p.bleed) parts += p.min_bleed > 0 ? _("bleed under %s").printf (Units.format (p.min_bleed, "mm")) : _("objects past the bleed");
            if (p.pasteboard) parts += _("objects on the pasteboard");
            if (p.empty) parts += _("empty frames and pages");
            if (p.accessibility) parts += _("accessibility");
            if (parts.length == 0) return _("No checks are turned on");
            string s = string.joinv (", ", parts);
            return s.substring (0, 1).up () + s.substring (1);
        }

        public static void manage (PublishWindow w, string current) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, _("Preflight Profiles"), 540, 640);
            var box = Dialogs.body (dlg);
            var bg = new PreferencesGroup (_("Built In"), _("Ready-made sets of checks; duplicate one to change it"));
            var cg = new PreferencesGroup (_("In This Publication"), _("Saved with the publication, so everyone who opens it checks the same way"));
            foreach (var p in PreflightProfile.all (pub)) {
                var prof = p;
                var row = new ActionRow (PreflightProfile.display_name (p.name), summary (p));
                if (p.name == current) row.add_prefix (new Image.from_icon_name ("object-select-symbolic"));
                var dup = new Button.with_label (p.builtin ? _("Duplicate") : _("Edit…"));
                dup.valign = Align.CENTER;
                dup.clicked.connect (() => {
                    dlg.close ();
                    if (prof.builtin) {
                        var copy = prof.clone ();
                        copy.builtin = false;
                        copy.name = unique_name (pub, _("%s Copy").printf (PreflightProfile.display_name (prof.name)));
                        edit (w, copy, true);
                    } else {
                        edit (w, prof, false);
                    }
                });
                row.add_suffix (dup);
                if (!p.builtin) {
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Profile");
                    del.clicked.connect (() => {
                        w.edit (_("Delete Preflight Profile"), () => {
                            pub.preflight_profiles.remove (prof);
                            if (pub.preflight_profile == prof.name) pub.preflight_profile = "";
                        });
                        dlg.close ();
                        w.preflight_panel.rebuild ();
                        w.schedule_preflight ();
                    });
                    row.add_suffix (del);
                }
                (p.builtin ? bg : cg).add_row (row);
            }
            box.append (bg);
            if (pub.preflight_profiles.size == 0) cg.add_row (new ActionRow (_("No profiles yet"), _("Duplicate a built-in profile or import one")));
            box.append (cg);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.halign = Align.END;
            bar.margin_top = 12;
            var imp = new Button.with_label (_("Import…"));
            imp.clicked.connect (() => {
                dlg.close ();
                import_profile (w);
            });
            bar.append (imp);
            var exp = new Button.with_label (_("Export Current…"));
            exp.clicked.connect (() => {
                dlg.close ();
                export_profile.begin (w, PreflightProfile.find (pub, current));
            });
            bar.append (exp);
            box.append (bar);
            dlg.open_dialog ();
        }

        public static string unique_name (Publication pub, string base_name) {
            string n = base_name;
            int i = 2;
            while (true) {
                bool clash = false;
                foreach (var p in PreflightProfile.all (pub)) if (p.name == n || PreflightProfile.display_name (p.name) == n) clash = true;
                if (!clash) return n;
                n = "%s %d".printf (base_name, i++);
            }
        }

        public static void edit (PublishWindow w, PreflightProfile p, bool is_new) {
            var pub = w.doc.pub;
            var dlg = Dialogs.make (w, is_new ? _("New Preflight Profile") : _("Edit Preflight Profile"), 540, 720);
            var box = Dialogs.body (dlg);
            var ng = new PreferencesGroup (_("Name"));
            var name = new EntryRow (_("Profile Name"));
            name.text = p.name;
            ng.add_row (name);
            var desc = new EntryRow (_("Description"));
            desc.text = p.description;
            ng.add_row (desc);
            box.append (ng);
            var lg = new PreferencesGroup (_("Links and Pictures"));
            var links = new SwitchRow (_("Missing or Modified Links"), null, p.links);
            lg.add_row (links);
            var images = new SwitchRow (_("Picture Resolution"), null, p.images);
            lg.add_row (images);
            var minp = spin (lg, _("Warn Below (ppi)"), 36, 2400, 1, p.min_ppi);
            var errp = spin (lg, _("Error Below (ppi)"), 36, 2400, 1, p.error_ppi);
            var maxp = spin (lg, _("Note Above (ppi, 0 for no limit)"), 0, 4800, 1, p.max_ppi);
            box.append (lg);
            var tg = new PreferencesGroup (_("Text"));
            var text = new SwitchRow (_("Overset Text"), null, p.text);
            tg.add_row (text);
            var fonts = new SwitchRow (_("Missing Fonts"), null, p.fonts);
            tg.add_row (fonts);
            var mint = spin (tg, _("Smallest Text Size (pt, 0 for any)"), 0, 72, 0.5, p.min_text, 1);
            box.append (tg);
            var colg = new PreferencesGroup (_("Colour"));
            var color = new SwitchRow (_("Check Colours"), null, p.color);
            colg.add_row (color);
            var rgb = new SwitchRow (_("Allow RGB"), _("Pictures and swatches may stay RGB"), p.allow_rgb);
            colg.add_row (rgb);
            var spot = new SwitchRow (_("Allow Spot Colours"), null, p.allow_spot);
            colg.add_row (spot);
            var ink = spin (colg, _("Total Ink Limit (%, 0 for none)"), 0, 400, 5, p.ink_limit);
            var transp = new SwitchRow (_("Report Transparency"), null, p.transparency);
            colg.add_row (transp);
            box.append (colg);
            var pgg = new PreferencesGroup (_("Page"));
            var bleed = new SwitchRow (_("Bleed"), _("Objects past the bleed and the document bleed size"), p.bleed);
            pgg.add_row (bleed);
            var minb = spin (pgg, _("Smallest Bleed (mm)"), 0, 50, 0.5, Units.to_unit (p.min_bleed, "mm"), 1);
            var paste = new SwitchRow (_("Objects on the Pasteboard"), null, p.pasteboard);
            pgg.add_row (paste);
            var empty = new SwitchRow (_("Empty Frames and Pages"), null, p.empty);
            pgg.add_row (empty);
            var a11y = new SwitchRow (_("Accessibility"), _("Alternative text, contrast, table headers, link text and title"), p.accessibility);
            pgg.add_row (a11y);
            box.append (pgg);
            string old_name = p.name;
            Dialogs.footer (dlg, is_new ? _("Create") : _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") {
                    w.show_error (_("Name the Profile"), _("A preflight profile needs a name."));
                    return;
                }
                foreach (var other in PreflightProfile.all (pub)) {
                    if (other != p && (other.name == n || PreflightProfile.display_name (other.name) == n)) {
                        w.show_error (_("Choose Another Name"), _("A profile called \"%s\" already exists.").printf (n));
                        return;
                    }
                }
                var np = new PreflightProfile (n);
                np.description = desc.text.strip ();
                np.links = links.switch_btn.active;
                np.images = images.switch_btn.active;
                np.min_ppi = minp.spin_btn.value;
                np.error_ppi = double.min (errp.spin_btn.value, minp.spin_btn.value);
                np.max_ppi = maxp.spin_btn.value;
                np.text = text.switch_btn.active;
                np.fonts = fonts.switch_btn.active;
                np.min_text = mint.spin_btn.value;
                np.color = color.switch_btn.active;
                np.allow_rgb = rgb.switch_btn.active;
                np.allow_spot = spot.switch_btn.active;
                np.ink_limit = ink.spin_btn.value;
                np.transparency = transp.switch_btn.active;
                np.bleed = bleed.switch_btn.active;
                np.min_bleed = Units.from_unit (minb.spin_btn.value, "mm");
                np.pasteboard = paste.switch_btn.active;
                np.empty = empty.switch_btn.active;
                np.accessibility = a11y.switch_btn.active;
                w.edit (is_new ? _("New Preflight Profile") : _("Edit Preflight Profile"), () => {
                    int at = pub.preflight_profiles.index_of (p);
                    if (at >= 0) pub.preflight_profiles[at] = np;
                    else pub.preflight_profiles.add (np);
                    if (is_new || pub.preflight_profile == old_name) pub.preflight_profile = np.name;
                });
                w.preflight_panel.mode = 0;
                w.preflight_panel.rebuild ();
                w.schedule_preflight ();
            });
            dlg.open_dialog ();
        }

        public static void import_profile (PublishWindow w) {
            var dialog = new FileDialog ();
            dialog.title = _("Import Preflight Profile");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (PublishWindow.filter (_("Preflight Profile"), { "pfprofile", "xml" }));
            dialog.filters = filters;
            dialog.initial_folder = w.default_folder ();
            dialog.open.begin (w, null, (o, res) => {
                try {
                    var f = dialog.open.end (res);
                    if (f == null || f.get_path () == null) return;
                    string text;
                    FileUtils.get_contents (f.get_path (), out text);
                    var p = PreflightProfile.from_file_text (text);
                    p.name = unique_name (w.doc.pub, p.name);
                    w.edit (_("Import Preflight Profile"), () => {
                        w.doc.pub.preflight_profiles.add (p);
                        w.doc.pub.preflight_profile = p.name;
                    });
                    w.preflight_panel.mode = 0;
                    w.toggle_panel ("preflight", true);
                    w.preflight_panel.rebuild ();
                    w.schedule_preflight ();
                } catch (Error e) {
                    if (e is IOError.CANCELLED || e is DialogError.DISMISSED) return;
                    w.show_error (_("Could Not Import the Profile"), e.message);
                }
            });
        }

        public static async void export_profile (PublishWindow w, PreflightProfile p) {
            var file = yield w.ask_save (_("Export Preflight Profile"), PreflightProfile.display_name (p.name) + ".pfprofile", { "pfprofile" }, _("Preflight Profile"));
            if (file == null) return;
            try {
                FileUtils.set_contents (file.get_path (), p.to_file_text ());
                w.toast (_("Exported \"%s\"").printf (file.get_basename ()));
            } catch (Error e) {
                w.show_error (_("Could Not Export"), e.message);
            }
        }
    }
}
