namespace Singularity.Apps.Publish {
    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string output;
        int status = Automation.run (args, out output);
        print ("%s", output);
        return status;
    }
}
