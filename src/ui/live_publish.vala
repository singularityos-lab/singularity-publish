namespace Singularity.Apps.Publish {

    [DBus (name = "dev.sinty.Collab.Publication1")]
    public class PublishCollabBus : Object {
        private unowned PublishApp app;

        public PublishCollabBus (PublishApp app) {
            this.app = app;
        }

        public void receive (string title, string payload, string from) throws Error {
            throw new IOError.NOT_SUPPORTED ("publications are shared in a session");
        }

        public void join (string session, string title, string snapshot, string role, string from) throws Error {
            var w = new PublishWindow (app);
            w.present ();
            PublishLive.join (w, session, snapshot, from);
        }
    }

    public class PublishLive : Object {
        private const string[] ORDER = { "settings", "meta", "layers", "swatches", "styles", "sections", "masters", "stories", "pages",
            "bookmarks", "schemes", "object-styles", "table-styles", "endnotes", "xml-map" };
        private const string[] KEYED = { "masters", "stories", "pages" };

        private unowned PublishWindow win;
        public LiveSession session;
        private Singularity.Collab.Document units;
        private Singularity.Collab.UnitsBinding binding;
        private Gee.HashSet<string> known_media = new Gee.HashSet<string> ();
        private ulong changed_id = 0;
        private Document? watched = null;
        private uint flush_id = 0;
        private bool applying = false;
        private int id_floor = 0;

        private PublishLive (PublishWindow win) {
            this.win = win;
            units = new Singularity.Collab.Document ();
            session = new LiveSession (Environment.get_real_name (), "publish-live", "/publish");
            binding = new Singularity.Collab.UnitsBinding (units, () => split (current_xml ()), (changed, who) => rebuild ());
            session.message.connect (on_message);
            session.state_requested.connect (() => session.publish_state (state ()));
            session.peer_joined.connect ((p) => win.toast (_("%s joined").printf (p.name)));
            session.peer_left.connect ((p) => win.toast (_("%s left").printf (p.name)));
            session.ended.connect ((reason) => {
                win.toast (reason);
                stop (win);
            });
        }

        public static PublishLive? of (PublishWindow win) {
            return win.get_data<PublishLive> ("publish-live");
        }

        private string current_xml () {
            return win.doc != null ? NativeFormat.to_xml (win.doc.pub) : "";
        }

        private static string child_key (Xml.Node* n, string group) {
            string id = n->get_prop ("id") ?? "";
            return "%s/%s".printf (group, id);
        }

        public static Gee.Map<string, string> split (string xml) {
            var map = new Gee.HashMap<string, string> ();
            if (xml == "") return map;
            Xml.Doc* doc;
            try {
                doc = NativeFormat.parse_keep_space (xml);
            } catch (Error e) {
                return map;
            }
            var root = doc->get_root_element ();
            map["root"] = root->get_prop ("version") ?? "1";
            for (Xml.Node* n = root->children; n != null; n = n->next) {
                if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (n->name in KEYED) {
                    string[] order = {};
                    for (Xml.Node* c = n->children; c != null; c = c->next) {
                        if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                        string key = child_key (c, n->name);
                        order += key;
                        var buf = new Xml.Buffer ();
                        buf.node_dump (doc, c, 0, 0);
                        map[key] = buf.content ();
                    }
                    map["order/" + n->name] = string.joinv ("\n", order);
                    continue;
                }
                var buf = new Xml.Buffer ();
                buf.node_dump (doc, n, 0, 0);
                map["el/" + n->name] = buf.content ();
            }
            delete doc;
            return map;
        }

        public static string assemble (Gee.Map<string, string> map, int next_id) {
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<publication version=\"%s\" next-id=\"%d\">".printf (map["root"] ?? "1", next_id));
            foreach (string name in ORDER) {
                if (name in KEYED) {
                    sb.append ("<%s>".printf (name));
                    var placed = new Gee.HashSet<string> ();
                    string order = map["order/" + name] ?? "";
                    foreach (string key in order.split ("\n")) {
                        if (key == "" || placed.contains (key) || !map.has_key (key)) continue;
                        sb.append (map[key]);
                        placed.add (key);
                    }
                    var rest = new Gee.ArrayList<string> ();
                    foreach (string key in map.keys) if (key.has_prefix (name + "/") && !placed.contains (key)) rest.add (key);
                    rest.sort ();
                    foreach (string key in rest) sb.append (map[key]);
                    sb.append ("</%s>".printf (name));
                    continue;
                }
                string? el = map["el/" + name];
                if (el != null) sb.append (el);
            }
            sb.append ("</publication>");
            return sb.str;
        }

        private Json.Object media_json (Gee.Collection<string>? only = null) {
            var o = new Json.Object ();
            if (win.doc == null) return o;
            foreach (var e in win.doc.pub.media.entries) {
                if (only != null && !only.contains (e.key)) continue;
                o.set_string_member (e.key, Base64.encode (e.value.get_data ()));
            }
            return o;
        }

        private Json.Object state () {
            var o = new Json.Object ();
            o.set_string_member ("units", units.snapshot ());
            o.set_object_member ("media", media_json ());
            return o;
        }

        private void claim_ids () {
            if (win.doc == null) return;
            if (id_floor == 0) id_floor = Random.int_range (1, 20000) * 100000;
            if (win.doc.pub.id_counter < id_floor) win.doc.pub.id_counter = id_floor;
        }

        private void rebuild () {
            if (win.doc == null) return;
            try {
                int counter = win.doc.pub.id_counter;
                var p = NativeFormat.from_xml (assemble (units.values (), counter));
                foreach (var e in win.doc.pub.media.entries) if (!p.media.has_key (e.key)) p.media[e.key] = e.value;
                p.base_dir = win.doc.pub.base_dir;
                p.id_counter = int.max (counter, p.id_counter);
                applying = true;
                win.doc.replace_publication (p);
                win.doc.modified = true;
                applying = false;
            } catch (Error e) {
                applying = false;
                warning ("publish: remote change skipped: %s", e.message);
            }
        }

        private void watch () {
            if (watched != null && changed_id != 0) watched.disconnect (changed_id);
            watched = win.doc;
            changed_id = 0;
            if (watched == null) return;
            foreach (string k in watched.pub.media.keys) known_media.add (k);
            changed_id = watched.changed.connect (() => {
                if (applying || flush_id != 0) return;
                flush_id = Timeout.add (300, () => {
                    flush_id = 0;
                    flush ();
                    return Source.REMOVE;
                });
            });
        }

        private void flush () {
            if (win.doc == null) return;
            var fresh = new Gee.ArrayList<string> ();
            foreach (string k in win.doc.pub.media.keys) if (!known_media.contains (k)) fresh.add (k);
            if (fresh.size > 0) {
                var m = new Json.Object ();
                m.set_string_member ("t", "media");
                m.set_object_member ("media", media_json (fresh));
                session.send (m);
                known_media.add_all (fresh);
            }
            binding.local_changed ();
            string? ops = units.take_outgoing ();
            if (ops == null) return;
            var o = new Json.Object ();
            o.set_string_member ("t", "units");
            o.set_string_member ("ops", ops);
            session.send (o);
        }

        private void on_message (Json.Object o) {
            string t = o.has_member ("t") ? o.get_string_member ("t") : "";
            if (t == "media" && win.doc != null) {
                var media = o.get_object_member ("media");
                foreach (string k in media.get_members ()) {
                    win.doc.pub.media[k] = new Bytes (Base64.decode (media.get_string_member (k)));
                    known_media.add (k);
                }
            } else if (t == "units") {
                units.merge (o.has_member ("who") ? o.get_string_member ("who") : "", o.get_string_member ("ops"));
            }
        }

        public static void share (PublishWindow win, Gtk.Widget anchor) {
            if (win.doc == null) return;
            var live = of (win);
            Singularity.Collab.Client.pick (anchor, true, (person) => {
                bool fresh = live == null;
                if (fresh) {
                    live = new PublishLive (win);
                    live.units.load_values (split (live.current_xml ()));
                    win.set_data<PublishLive> ("publish-live", live);
                }
                string title = win.doc.pub.meta.title != "" ? win.doc.pub.meta.title : _("Publication");
                live.session.host_collab.begin (live.state (), person, "Publication", title, (o, res) => {
                    try {
                        live.session.host_collab.end (res);
                        if (fresh) {
                            live.claim_ids ();
                            live.watch ();
                        }
                        win.toast (_("Invitation sent to %s").printf (person.name));
                    } catch (Error e) {
                        win.toast (e.message);
                        if (fresh) stop (win);
                    }
                });
            });
        }

        public static void join (PublishWindow win, string session_id, string snapshot, string from) {
            var live = new PublishLive (win);
            win.set_data<PublishLive> ("publish-live", live);
            live.session.welcome.connect ((state) => {
                live.units.load (state.get_string_member ("units"));
                try {
                    var p = NativeFormat.from_xml (assemble (live.units.values (), 1));
                    if (state.has_member ("media")) {
                        var media = state.get_object_member ("media");
                        foreach (string k in media.get_members ()) p.media[k] = new Bytes (Base64.decode (media.get_string_member (k)));
                    }
                    win.load_document (new Document (p));
                    live.claim_ids ();
                    live.binding.adopt_local ();
                    live.watch ();
                    win.toast (_("You are working with %s").printf (from));
                } catch (Error e) {
                    win.toast (e.message);
                    stop (win);
                }
            });
            live.session.join_collab (session_id, snapshot);
        }

        public static void stop (PublishWindow win) {
            var live = of (win);
            if (live == null) return;
            win.set_data<PublishLive> ("publish-live", null);
            if (live.watched != null && live.changed_id != 0) live.watched.disconnect (live.changed_id);
            if (live.flush_id != 0) Source.remove (live.flush_id);
            live.session.leave ();
        }
    }
}
