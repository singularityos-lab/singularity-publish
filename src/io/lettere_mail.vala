namespace Singularity.Apps.Publish {

    public errordomain LettereError {
        UNAVAILABLE,
        DENIED,
        NO_ACCOUNT,
        INVALID
    }

    public class MailOutcome {
        public string to;
        public string subject;
        public bool sent;
        public string error;

        public MailOutcome (string to, string subject, bool sent, string error) {
            this.to = to;
            this.subject = subject;
            this.sent = sent;
            this.error = error;
        }
    }

    public class MailStop : Object {
        public bool stopped { get; private set; default = false; }
        public signal void requested ();

        public void stop () {
            if (stopped) return;
            stopped = true;
            requested ();
        }
    }

    public class LettereMail {
        public const string BUS_NAME = "dev.sinty.lettere";
        public const string OBJECT_PATH = "/dev/sinty/lettere";
        public const string INTERFACE = "dev.sinty.Lettere.Mail";

        public delegate void Progress (int done, int total, MailOutcome last);

        public static uint8[] for_sending (uint8[] message) {
            int end = message.length;
            for (int i = 0; i + 1 < message.length; i++) {
                if (message[i] == '\n' && (message[i + 1] == '\n' || (message[i + 1] == '\r' && i + 2 < message.length && message[i + 2] == '\n'))) {
                    end = i + 1;
                    break;
                }
            }
            var b = new ByteArray ();
            int start = 0;
            bool skipping = false;
            while (start < end) {
                int stop = start;
                while (stop < end && message[stop] != '\n') stop++;
                int next = int.min (stop + 1, end);
                bool cont = message[start] == ' ' || message[start] == '\t';
                if (!cont) {
                    var sb = new StringBuilder ();
                    for (int k = start; k < stop && k < start + 9; k++) sb.append_c (((char) message[k]).tolower ());
                    skipping = sb.str.has_prefix ("x-unsent:");
                }
                if (!skipping) b.append (message[start:next]);
                start = next;
            }
            if (end < message.length) b.append (message[end:message.length]);
            return b.steal ();
        }

        private static Error translate (Error e) {
            string? remote = DBusError.get_remote_error (e);
            if (remote != null) DBusError.strip_remote_error (e);
            if (remote == "dev.sinty.Lettere.Mail.Error.Denied") return new LettereError.DENIED (_("Sending was not allowed in Lettere"));
            if (remote == "dev.sinty.Lettere.Mail.Error.NoAccount") return new LettereError.NO_ACCOUNT (_("Lettere has no mail account that can send. Add one in Lettere first."));
            if (remote == "dev.sinty.Lettere.Mail.Error.Invalid") return new LettereError.INVALID (e.message);
            if (e is DBusError.SERVICE_UNKNOWN || e is DBusError.NAME_HAS_NO_OWNER || e is DBusError.UNKNOWN_METHOD || e is DBusError.UNKNOWN_INTERFACE || e is DBusError.UNKNOWN_OBJECT || e is DBusError.SPAWN_SERVICE_NOT_FOUND) return new LettereError.UNAVAILABLE (_("Lettere is not installed, so messages cannot be sent from Publish"));
            if (e is DBusError || remote != null) return new LettereError.UNAVAILABLE (e.message);
            return e;
        }

        public static async bool available (DBusConnection? bus = null) {
            try {
                var conn = bus ?? yield Bus.get (BusType.SESSION);
                foreach (string method in new string[] { "NameHasOwner", "ListActivatableNames" }) {
                    var r = yield conn.call ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", method, method == "NameHasOwner" ? new Variant ("(s)", BUS_NAME) : null, null, DBusCallFlags.NONE, 5000, null);
                    var v = r.get_child_value (0);
                    if (v.is_of_type (VariantType.BOOLEAN)) {
                        if (v.get_boolean ()) return true;
                        continue;
                    }
                    foreach (string n in v.get_strv ()) if (n == BUS_NAME) return true;
                }
            } catch (Error e) {
            }
            return false;
        }

        public static async Gee.ArrayList<MailOutcome> send_all (Gee.List<EmailMessage> messages, string account, Progress? progress, MailStop? cancel, DBusConnection? bus = null) throws Error {
            DBusConnection conn;
            try {
                conn = bus ?? yield Bus.get (BusType.SESSION);
            } catch (Error e) {
                throw translate (e);
            }
            var results = new Gee.HashMap<int64?, MailOutcome> ((v) => int64_hash (v), (a, b) => a == b);
            var index = new Gee.HashMap<int64?, int> ((v) => int64_hash (v), (a, b) => a == b);
            var dropped = new Gee.HashSet<int64?> ((v) => int64_hash (v), (a, b) => a == b);
            int64[] ids = {};
            int done = 0;
            bool waiting = false;
            uint sub = 0;
            uint poll = 0;
            ulong stop = 0;
            var to_cancel = new Gee.ArrayList<int64?> ();

            SourceFunc settle = () => {
                if (waiting && results.size + dropped.size >= ids.length) {
                    waiting = false;
                    Idle.add (send_all.callback);
                }
                return false;
            };

            sub = conn.signal_subscribe (null, INTERFACE, null, OBJECT_PATH, null, DBusSignalFlags.NONE, (c, sender, path, iface, member, parameters) => {
                if (member != "MessageSent" && member != "MessageFailed") return;
                int64 id = parameters.get_child_value (0).get_int64 ();
                if (!index.has_key (id) || results.has_key (id) || dropped.contains (id)) return;
                var m = messages[index[id]];
                MailOutcome o;
                if (member == "MessageSent") {
                    o = new MailOutcome (m.to, m.subject, true, "");
                } else {
                    o = new MailOutcome (m.to, m.subject, false, parameters.get_child_value (1).get_string ());
                    to_cancel.add (id);
                }
                results[id] = o;
                done++;
                if (progress != null) progress (done, ids.length, o);
                settle ();
            });

            var list = new VariantBuilder (new VariantType ("aay"));
            foreach (var m in messages) list.add_value (new Variant.from_bytes (new VariantType ("ay"), new Bytes (for_sending (m.data)), true));
            var opts = new VariantBuilder (new VariantType ("a{sv}"));
            opts.add ("{sv}", "app-name", new Variant.string ("Publish"));
            try {
                var r = yield conn.call (BUS_NAME, OBJECT_PATH, INTERFACE, "QueueMessages", new Variant ("(s@aay@a{sv})", account, list.end (), opts.end ()), new VariantType ("(ax)"), DBusCallFlags.NONE, int.MAX, null);
                var arr = r.get_child_value (0);
                for (size_t i = 0; i < arr.n_children (); i++) {
                    int64 id = arr.get_child_value (i).get_int64 ();
                    ids += id;
                    index[id] = (int) i;
                }
            } catch (Error e) {
                conn.signal_unsubscribe (sub);
                throw translate (e);
            }

            poll = Timeout.add (1000, () => {
                int64[] open = {};
                foreach (var id in ids) if (!results.has_key (id) && !dropped.contains (id)) open += id;
                if (open.length == 0) return true;
                conn.call.begin (BUS_NAME, OBJECT_PATH, INTERFACE, "Status", new Variant.tuple ({ new Variant.array (VariantType.INT64, ints (open)) }), new VariantType ("(a(xss))"), DBusCallFlags.NONE, 5000, null, (obj, res) => {
                    try {
                        var st = conn.call.end (res).get_child_value (0);
                        for (size_t i = 0; i < st.n_children (); i++) {
                            int64 id;
                            string state, error;
                            st.get_child_value (i).get ("(xss)", out id, out state, out error);
                            if (!index.has_key (id) || results.has_key (id) || dropped.contains (id)) continue;
                            var m = messages[index[id]];
                            MailOutcome? o = null;
                            if (state == "sent") o = new MailOutcome (m.to, m.subject, true, "");
                            else if (state == "retrying") {
                                o = new MailOutcome (m.to, m.subject, false, error);
                                to_cancel.add (id);
                            } else if (state == "unknown") {
                                dropped.add (id);
                            }
                            if (o != null) {
                                results[id] = o;
                                done++;
                                if (progress != null) progress (done, ids.length, o);
                            }
                        }
                        foreach (var id in to_cancel) withdraw.begin (conn, id);
                        to_cancel.clear ();
                        settle ();
                    } catch (Error e) {
                    }
                });
                return true;
            });

            if (cancel != null) {
                stop = cancel.requested.connect (() => {
                    Idle.add (() => {
                        int64[] open = {};
                        foreach (var id in ids) if (!results.has_key (id) && !dropped.contains (id)) open += id;
                        if (open.length == 0) return false;
                        conn.call.begin (BUS_NAME, OBJECT_PATH, INTERFACE, "Cancel", new Variant.tuple ({ new Variant.array (VariantType.INT64, ints (open)) }), new VariantType ("(ax)"), DBusCallFlags.NONE, 5000, null, (obj, res) => {
                            try {
                                var gone = conn.call.end (res).get_child_value (0);
                                for (size_t i = 0; i < gone.n_children (); i++) dropped.add (gone.get_child_value (i).get_int64 ());
                            } catch (Error e) {
                            }
                            settle ();
                        });
                        return false;
                    });
                });
            }

            if (ids.length > 0 && results.size + dropped.size < ids.length) {
                waiting = true;
                yield;
            }
            foreach (var id in to_cancel) yield withdraw (conn, id);
            if (poll != 0) Source.remove (poll);
            conn.signal_unsubscribe (sub);
            if (cancel != null && stop != 0) cancel.disconnect (stop);
            var collected = new Gee.ArrayList<MailOutcome> ();
            foreach (var id in ids) if (results.has_key (id)) collected.add (results[id]);
            return collected;
        }

        private static Variant[] ints (int64[] list) {
            Variant[] v = {};
            foreach (var x in list) v += new Variant.int64 (x);
            return v;
        }

        private static async void withdraw (DBusConnection conn, int64 id) {
            try {
                yield conn.call (BUS_NAME, OBJECT_PATH, INTERFACE, "Cancel", new Variant.tuple ({ new Variant.array (VariantType.INT64, { new Variant.int64 (id) }) }), new VariantType ("(ax)"), DBusCallFlags.NONE, 5000, null);
            } catch (Error e) {
            }
        }

        public static string report (Gee.List<MailOutcome> outcomes) {
            var sb = new StringBuilder ();
            int ok = 0;
            foreach (var o in outcomes) if (o.sent) ok++;
            sb.append (_("Sent %d of %d messages").printf (ok, outcomes.size) + "\n\n");
            foreach (var o in outcomes) sb.append ("%s\t%s\t%s\n".printf (o.sent ? _("sent") : _("failed"), o.to, o.sent ? o.subject : o.error));
            return sb.str;
        }
    }
}
