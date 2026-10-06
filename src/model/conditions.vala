namespace Singularity.Apps.Publish {

    public class TextCondition {
        public string name;
        public bool visible = true;
        public string color = "#e0457b";

        public TextCondition (string name) {
            this.name = name;
        }

        public TextCondition clone () {
            var c = new TextCondition (name);
            c.visible = visible;
            c.color = color;
            return c;
        }
    }

    public class ConditionSet {
        public string name;
        public Gee.HashMap<string, bool> states = new Gee.HashMap<string, bool> ();

        public ConditionSet (string name) {
            this.name = name;
        }

        public ConditionSet clone () {
            var s = new ConditionSet (name);
            foreach (var e in states.entries) s.states[e.key] = e.value;
            return s;
        }
    }

    public class Conditions {
        public static TextCondition? find (Publication pub, string name) {
            foreach (var c in pub.conditions) if (c.name == name) return c;
            return null;
        }

        public static bool hidden (Publication pub, string condition) {
            if (condition == "") return false;
            foreach (string n in condition.split (",")) {
                var c = find (pub, n.strip ());
                if (c != null && c.visible) return false;
            }
            return true;
        }

        public static ConditionSet capture (Publication pub, string name) {
            var s = new ConditionSet (name);
            foreach (var c in pub.conditions) s.states[c.name] = c.visible;
            return s;
        }

        public static void apply_set (Publication pub, ConditionSet s) {
            foreach (var c in pub.conditions) if (s.states.has_key (c.name)) c.visible = s.states[c.name];
            pub.active_condition_set = s.name;
        }

        public static void write (Publication pub, XmlOut x) {
            if (pub.conditions.size == 0) return;
            x.start ("conditions").a ("active-set", pub.active_condition_set);
            foreach (var c in pub.conditions) x.start ("condition").a ("name", c.name).ai ("visible", c.visible ? 1 : 0).a ("color", c.color).end ();
            foreach (var s in pub.condition_sets) {
                x.start ("condition-set").a ("name", s.name);
                foreach (var e in s.states.entries) x.start ("state").a ("condition", e.key).ai ("visible", e.value ? 1 : 0).end ();
                x.end ();
            }
            x.end ();
        }

        public static void read (Publication pub, Xml.Node* n) {
            if (n == null) return;
            pub.active_condition_set = XmlIn.attr (n, "active-set") ?? "";
            foreach (var cn in XmlIn.elements (n, "condition")) {
                var c = new TextCondition (XmlIn.attr (cn, "name") ?? "");
                c.visible = XmlIn.int_attr (cn, "visible", 1) == 1;
                c.color = XmlIn.attr (cn, "color") ?? "#e0457b";
                pub.conditions.add (c);
            }
            foreach (var sn in XmlIn.elements (n, "condition-set")) {
                var s = new ConditionSet (XmlIn.attr (sn, "name") ?? "");
                foreach (var st in XmlIn.elements (sn, "state")) s.states[XmlIn.attr (st, "condition") ?? ""] = XmlIn.int_attr (st, "visible", 1) == 1;
                pub.condition_sets.add (s);
            }
        }
    }
}
