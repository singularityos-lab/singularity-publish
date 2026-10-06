namespace Singularity.Apps.Publish {

    public class BlockPack {
        public static uint8[] pack (Publication src, Gee.List<Item> items) throws Error {
            var p = Publication.create (src.settings.clone (), 1);
            p.styles = src.styles.clone ();
            p.swatches.clear ();
            foreach (var sw in src.swatches) p.swatches.add (sw.clone ());
            var page = p.pages[0];
            foreach (var it in items) {
                var c = it.clone ();
                copy_refs (src, p, c);
                page.items.add (c);
            }
            return NativeFormat.write (p, false);
        }

        private static void copy_refs (Publication src, Publication dst, Item it) {
            var t = it as TextFrame;
            if (t != null && src.stories.has_key (t.story)) {
                var st = src.stories[t.story].clone ();
                st.frames.clear ();
                st.frames.add (t.id);
                dst.stories[t.story] = st;
            }
            var im = it as ImageFrame;
            if (im != null && im.media != "" && src.media.has_key (im.media)) dst.media[im.media] = src.media[im.media];
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) copy_refs (src, dst, c);
        }

        public static Gee.ArrayList<Item> unpack (Publication dst, uint8[] data, Gee.List<Item> target) throws Error {
            var p = NativeFormat.read (data);
            var made = new Gee.ArrayList<Item> ();
            foreach (var ps in p.styles.paragraph) if (dst.styles.find_paragraph (ps.name) == null) dst.styles.paragraph.add (ps.clone ());
            foreach (var cs in p.styles.character) if (dst.styles.find_character (cs.name) == null) dst.styles.character.add (cs.clone ());
            foreach (var sw in p.swatches) if (dst.swatch (sw.name) == null) dst.swatches.add (sw.clone ());
            foreach (var kv in p.media.entries) if (!dst.media.has_key (kv.key)) dst.media[kv.key] = kv.value;
            if (p.pages.size == 0) return made;
            foreach (var it in p.pages[0].items) {
                var c = it.clone ();
                bring (p, dst, c);
                c.layer = dst.default_layer ().id;
                target.add (c);
                made.add (c);
            }
            return made;
        }

        private static void bring (Publication src, Publication dst, Item it) {
            int old_story = (it is TextFrame) ? ((TextFrame) it).story : -1;
            it.id = dst.next_id ();
            var t = it as TextFrame;
            if (t != null) {
                var st = src.stories.has_key (old_story) ? src.stories[old_story].clone () : new Story (0);
                st.id = dst.next_id ();
                st.frames.clear ();
                st.frames.add (t.id);
                dst.stories[st.id] = st;
                t.story = st.id;
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var c in row) c.story.id = dst.next_id ();
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) bring (src, dst, c);
        }
    }
}
