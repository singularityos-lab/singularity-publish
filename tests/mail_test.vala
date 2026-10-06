using Singularity.Apps.Publish;

[DBus (name = "dev.sinty.Lettere.Mail.Error")]
public errordomain FakeMailError {
    DENIED
}

public struct FakeState {
    public int64 id;
    public string state;
    public string error;
}

[DBus (name = "dev.sinty.Lettere.Mail")]
public class FakeLettere : Object {
    [DBus (visible = false)]
    public string mode = "signals";
    [DBus (visible = false)]
    public Gee.ArrayList<string> messages = new Gee.ArrayList<string> ();
    [DBus (visible = false)]
    public Gee.ArrayList<int64?> cancelled = new Gee.ArrayList<int64?> ();
    [DBus (visible = false)]
    public string app_name = "";
    private DBusConnection conn;
    private Gee.HashMap<int64?, string> state = new Gee.HashMap<int64?, string> ((v) => int64_hash (v), (a, b) => a == b);
    private int64 next = 100;

    [DBus (visible = false)]
    public FakeLettere (DBusConnection conn) throws Error {
        this.conn = conn;
        conn.register_object (LettereMail.OBJECT_PATH, this);
    }

    public int64[] queue_messages (string account, [DBus (signature = "aay")] Variant list, [DBus (signature = "a{sv}")] Variant opts, BusName sender) throws FakeMailError, DBusError, IOError {
        if (mode == "deny") throw new FakeMailError.DENIED ("The person did not allow sending");
        var an = opts.lookup_value ("app-name", VariantType.STRING);
        if (an != null) app_name = an.get_string ();
        int64[] raw = {};
        for (size_t i = 0; i < list.n_children (); i++) {
            var bytes = list.get_child_value (i).get_data_as_bytes ();
            var sb = new StringBuilder ();
            sb.append_len ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
            messages.add (sb.str);
            int64 id = next++;
            raw += id;
            state[id] = sb.str.contains ("To: reject@example.org") ? "retrying" : "sent";
        }
        if (mode == "signals") {
            string dest = (string) sender;
            int64[] copy = raw;
            Timeout.add (30, () => {
                foreach (var id in copy) {
                    try {
                        if (state[id] == "sent") conn.emit_signal (dest, LettereMail.OBJECT_PATH, LettereMail.INTERFACE, "MessageSent", new Variant ("(x)", id));
                        else conn.emit_signal (dest, LettereMail.OBJECT_PATH, LettereMail.INTERFACE, "MessageFailed", new Variant ("(xs)", id, "550 no such user"));
                    } catch (Error e) {
                    }
                }
                return false;
            });
        }
        return raw;
    }

    public FakeState[] status (int64[] ids) throws DBusError, IOError {
        FakeState[] r = {};
        foreach (var id in ids) {
            string st = state.has_key (id) ? state[id] : "unknown";
            if (mode == "hold" && st == "sent") st = "queued";
            r += FakeState () { id = id, state = st, error = st == "retrying" ? "550 no such user" : "" };
        }
        return r;
    }

    public int64[] cancel (int64[] ids) throws DBusError, IOError {
        foreach (var id in ids) {
            cancelled.add (id);
            state.unset (id);
        }
        return ids;
    }
}

Gee.ArrayList<EmailMessage> messages () {
    var list = new Gee.ArrayList<EmailMessage> ();
    string[] to = { "Ada <ada@example.org>", "reject@example.org", "bo@example.org" };
    foreach (string t in to) {
        var parts = new Gee.ArrayList<HtmlAsset> ();
        var data = EmailMerge.compose ("", t, "Autumn offer", "<p>Hello</p>", parts, "Hello\nbye\n", null, "offer.pdf");
        list.add (new EmailMessage (t, "Autumn offer", "", data));
    }
    return list;
}

Gee.ArrayList<MailOutcome>? send_batch (DBusConnection client, MailStop? cancel, out string error, out int progress_calls) {
    var loop = new MainLoop ();
    Gee.ArrayList<MailOutcome>? result = null;
    string err = "";
    int calls = 0;
    LettereMail.send_all.begin (messages (), "", (done, total, last) => {
        calls++;
    }, cancel, client, (o, r) => {
        try {
            result = LettereMail.send_all.end (r);
        } catch (Error e) {
            err = e.message;
        }
        loop.quit ();
    });
    Timeout.add_seconds (20, () => {
        loop.quit ();
        return false;
    });
    loop.run ();
    error = err;
    progress_calls = calls;
    return result;
}

DBusConnection open_bus (string address) {
    try {
        return new DBusConnection.for_address_sync (address, DBusConnectionFlags.AUTHENTICATION_CLIENT | DBusConnectionFlags.MESSAGE_BUS_CONNECTION, null, null);
    } catch (Error e) {
        error (e.message);
    }
}

void own (DBusConnection c, string name) {
    try {
        c.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", new Variant ("(su)", name, 4), null, DBusCallFlags.NONE, -1, null);
    } catch (Error e) {
        error (e.message);
    }
}

void test_lettere () {
    Environment.unset_variable ("DBUS_SESSION_BUS_ADDRESS");
    var bus = new TestDBus (TestDBusFlags.NONE);
    bus.up ();
    string address = bus.get_bus_address ();
    var client = open_bus (address);

    bool present = false;
    var l0 = new MainLoop ();
    LettereMail.available.begin (client, (o, r) => {
        present = LettereMail.available.end (r);
        l0.quit ();
    });
    l0.run ();
    assert (!present);

    string err;
    int calls;
    var none = send_batch (client, null, out err, out calls);
    assert (none == null && err.contains ("Lettere is not installed"));

    var service = open_bus (address);
    own (service, LettereMail.BUS_NAME);
    FakeLettere fake;
    try {
        fake = new FakeLettere (service);
    } catch (Error e) {
        error (e.message);
    }
    var l1 = new MainLoop ();
    LettereMail.available.begin (client, (o, r) => {
        present = LettereMail.available.end (r);
        l1.quit ();
    });
    l1.run ();
    assert (present);

    var out_list = send_batch (client, null, out err, out calls);
    assert (err == "");
    assert (out_list != null && out_list.size == 3);
    assert (out_list[0].sent && !out_list[1].sent && out_list[2].sent);
    assert (out_list[1].error.contains ("550"));
    assert (calls == 3);
    assert (fake.app_name == "Publish");
    assert (fake.messages.size == 3);
    assert (!fake.messages[0].contains ("X-Unsent"));
    assert (fake.messages[0].contains ("To: Ada <ada@example.org>"));
    assert (fake.messages[0].contains ("Subject: Autumn offer"));
    assert (fake.cancelled.size == 1 && fake.cancelled[0] == 101);
    string report = LettereMail.report (out_list);
    assert (report.contains ("Sent 2 of 3") && report.contains ("reject@example.org"));

    fake.mode = "poll";
    fake.messages.clear ();
    var polled = send_batch (client, null, out err, out calls);
    assert (err == "" && polled != null && polled.size == 3 && polled[0].sent && !polled[1].sent);

    fake.mode = "hold";
    fake.cancelled.clear ();
    var cancel = new MailStop ();
    Timeout.add (1500, () => {
        cancel.stop ();
        return false;
    });
    var held = send_batch (client, cancel, out err, out calls);
    assert (err == "" && held != null);
    assert (held.size == 1 && !held[0].sent);
    assert (fake.cancelled.size >= 2);

    fake.mode = "deny";
    var denied = send_batch (client, null, out err, out calls);
    assert (denied == null && err.contains ("not allowed"));

    try {
        client.close_sync ();
        service.close_sync ();
    } catch (Error e) {
    }
    bus.down ();
}

string s_of (uint8[] d) {
    var sb = new StringBuilder.sized (d.length + 1);
    sb.append_len ((string) d, d.length);
    return sb.str;
}

void test_helpers () {
    string f = s_of (LettereMail.for_sending ("From: x\r\nX-Unsent: 1\r\nTo: y\r\n\r\nX-Unsent: body".data));
    assert (f == "From: x\r\nTo: y\r\n\r\nX-Unsent: body");
    string g = s_of (LettereMail.for_sending ("x-unsent: 1\n  folded\nSubject: s\n\nbody".data));
    assert (g == "Subject: s\n\nbody");
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/mail/helpers", test_helpers);
    Test.add_func ("/mail/lettere", test_lettere);
    return Test.run ();
}
