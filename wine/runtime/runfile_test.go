package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunfileManifestDirectoryMappings(t *testing.T) {
	root := t.TempDir()
	parent, nested := filepath.Join(root, "parent"), filepath.Join(root, "nested directory")
	for _, dir := range []string{parent, nested} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	exact := filepath.Join(root, "exact café.txt")
	if err := os.WriteFile(exact, []byte("exact"), 0600); err != nil {
		t.Fatal(err)
	}
	child := filepath.Join(nested, "data café.txt")
	if err := os.WriteFile(child, []byte("nested"), 0600); err != nil {
		t.Fatal(err)
	}
	escaped := func(value string) string { return strings.NewReplacer(`\`, `\b`, " ", `\s`, "\n", `\n`).Replace(value) }
	manifest := filepath.Join(root, "MANIFEST")
	content := "repo/tree/nested " + nested + "\nrepo/tree " + parent + "\n" +
		"repo/tree/nested/exact " + exact + "\n" +
		" " + escaped("repo/tree with spaces") + " " + escaped(nested) + "\n" +
		" " + escaped("repo/tree with spaces/exact") + " " + escaped(exact) + "\n"
	if err := os.WriteFile(manifest, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("RUNFILES_DIR", filepath.Join(root, "missing"))
	t.Setenv("TEST_SRCDIR", filepath.Join(root, "missing"))
	t.Setenv("RUNFILES_MANIFEST_FILE", manifest)
	for _, test := range []struct{ name, logical, want string }{
		{"directory child", "repo/tree/nested/data café.txt", child},
		{"exact entry wins", "repo/tree/nested/exact", exact},
		{"escaped directory key", "repo/tree with spaces/data café.txt", child},
		{"escaped exact entry wins", "repo/tree with spaces/exact", exact},
	} {
		t.Run(test.name, func(t *testing.T) {
			actual, err := runfile(test.logical)
			if err != nil || actual != test.want {
				t.Fatalf("runfile(%q) = %q, %v; want %q", test.logical, actual, err, test.want)
			}
		})
	}
	if path, err := runfile("repo/tree-other/data café.txt"); err == nil {
		t.Fatalf("directory-prefix boundary matched unrelated path: %s", path)
	}
}
