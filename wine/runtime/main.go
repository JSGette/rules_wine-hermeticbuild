// rules_wine's compiler-free runtime entrypoint. See tools/build_runtime.sh.
package main

import (
	"debug/elf"
	"debug/macho"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type configuration struct {
	Backend    string            `json:"backend"`
	Arch       string            `json:"arch"`
	Loader     string            `json:"loader"`
	Server     string            `json:"server"`
	Payload    string            `json:"payload"`
	Args       []string          `json:"args"`
	Env        map[string]string `json:"env"`
	Runfiles   bool              `json:"runfiles"`
	RuntimeEnv map[string]string `json:"runtime_env"`
}

func fatal(err error) { fmt.Fprintln(os.Stderr, "rules_wine:", err); os.Exit(125) }

func runfile(path string) (string, error) {
	if filepath.IsAbs(path) {
		return path, nil
	}
	dirs := []string{os.Getenv("RUNFILES_DIR"), os.Getenv("TEST_SRCDIR")}
	self, _ := filepath.Abs(os.Args[0])
	dirs = append(dirs, self+".runfiles")
	for _, dir := range dirs {
		if dir == "" {
			continue
		}
		candidate := filepath.Join(dir, filepath.FromSlash(path))
		if _, err := os.Stat(candidate); err == nil {
			return filepath.Abs(candidate)
		}
	}
	manifest := os.Getenv("RUNFILES_MANIFEST_FILE")
	if manifest == "" {
		manifest = self + ".runfiles_manifest"
	}
	if data, err := os.ReadFile(manifest); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			escaped := strings.HasPrefix(line, " ")
			if escaped {
				line = line[1:]
			}
			key, value, found := strings.Cut(line, " ")
			if escaped {
				decoder := strings.NewReplacer(`\s`, " ", `\n`, "\n", `\b`, `\`)
				key, value = decoder.Replace(key), decoder.Replace(value)
			}
			if !found {
				value = key
			}
			if key == path {
				return filepath.Abs(value)
			}
		}
	}
	return "", fmt.Errorf("runfile %q not found (RUNFILES_DIR/manifest)", path)
}

func windowsPath(path string) string {
	if runtime.GOOS == "windows" {
		return path
	}
	full, _ := filepath.Abs(path)
	return "Z:" + strings.ReplaceAll(full, "/", "\\")
}

func convert(value string, _ bool) (string, error) {
	for _, marker := range []string{"{windows_path:", "{windows_runfile:"} {
		for strings.Contains(value, marker) {
			start := strings.Index(value, marker)
			end := strings.IndexByte(value[start:], '}')
			if end < 0 {
				return "", errors.New("unterminated Windows path interpolation")
			}
			end += start
			path := value[start+len(marker) : end]
			if marker == "{windows_runfile:" {
				var err error
				path, err = runfile(path)
				if err != nil {
					return "", err
				}
			}
			value = value[:start] + windowsPath(path) + value[end+1:]
		}
	}
	return value, nil
}

func validatePE(path, arch string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	header := make([]byte, 64)
	if _, err = io.ReadFull(file, header); err != nil {
		return fmt.Errorf("payload PE header: %w", err)
	}
	if string(header[:2]) != "MZ" {
		return errors.New("payload is not a Windows PE executable")
	}
	_, err = file.Seek(int64(binary.LittleEndian.Uint32(header[60:])), 0)
	if err != nil {
		return err
	}
	pe := make([]byte, 6)
	if _, err = io.ReadFull(file, pe); err != nil {
		return err
	}
	want := uint16(0x8664)
	if arch == "aarch64" {
		want = 0xaa64
	}
	if string(pe[:4]) != "PE\x00\x00" || binary.LittleEndian.Uint16(pe[4:]) != want {
		return fmt.Errorf("payload PE machine does not match %s", arch)
	}
	return nil
}

func validateNative(path, arch string) error {
	if runtime.GOOS == "linux" {
		file, err := elf.Open(path)
		if err != nil {
			return fmt.Errorf("native Wine executable %s: %w", path, err)
		}
		defer file.Close()
		want := elf.EM_X86_64
		if arch == "aarch64" {
			want = elf.EM_AARCH64
		}
		if file.Machine != want || file.Class != elf.ELFCLASS64 {
			return fmt.Errorf("Wine executable CPU does not match %s: %s", arch, path)
		}
		return nil
	}
	want := macho.CpuAmd64
	if arch == "aarch64" {
		want = macho.CpuArm64
	}
	if file, err := macho.Open(path); err == nil {
		defer file.Close()
		if file.Cpu == want {
			return nil
		}
		return fmt.Errorf("Wine executable CPU does not match %s: %s", arch, path)
	}
	if file, err := macho.OpenFat(path); err == nil {
		defer file.Close()
		for _, slice := range file.Arches {
			if slice.Cpu == want {
				return nil
			}
		}
	}
	return fmt.Errorf("Wine executable lacks native %s Mach-O slice (no Rosetta fallback): %s", arch, path)
}

func execute(program string, args []string, env []string, timeout time.Duration, signals <-chan os.Signal) int {
	cmd := exec.Command(program, args...)
	cmd.Env, cmd.Stdin, cmd.Stdout, cmd.Stderr = env, os.Stdin, os.Stdout, os.Stderr
	isolate(cmd)
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "rules_wine:", err)
		return 125
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	var timer <-chan time.Time
	if timeout > 0 {
		timer = time.After(timeout)
	}
	select {
	case err := <-done:
		if err == nil {
			return 0
		}
		if exit, ok := err.(*exec.ExitError); ok {
			code := processExitStatus(exit.ProcessState)
			if runtime.GOOS == "windows" {
				return code
			}
			if code >= 0 && code <= 255 {
				return code
			}
			fmt.Fprintf(os.Stderr, "rules_wine: Windows/process exit status %d mapped to 1\n", code)
			return 1
		}
		return 125
	case sig := <-signals:
		fmt.Fprintln(os.Stderr, "rules_wine: cancelling:", sig)
		terminate(cmd)
		<-done
		return 128 + signalNumber(sig)
	case <-timer:
		fmt.Fprintln(os.Stderr, "rules_wine: initialization/cleanup timed out")
		terminate(cmd)
		<-done
		return 124
	}
}

func invoke(c configuration, extra []string) int {
	if c.Arch != "x86_64" && c.Arch != "aarch64" {
		fmt.Fprintln(os.Stderr, "rules_wine: unsupported payload architecture", c.Arch)
		return 125
	}
	expected := "amd64"
	if c.Arch == "aarch64" {
		expected = "arm64"
	}
	if runtime.GOARCH != expected {
		fmt.Fprintln(os.Stderr, "rules_wine: CPU translation is unsupported")
		return 125
	}
	resolve := func(path string) string {
		if path == "" {
			return path
		}
		var err error
		if c.Runfiles {
			path, err = runfile(path)
		} else {
			path, err = filepath.Abs(path)
		}
		if err != nil {
			fatal(err)
		}
		canonical, err := filepath.EvalSymlinks(path)
		if err != nil {
			fatal(err)
		}
		return canonical
	}
	c.Payload, c.Loader, c.Server = resolve(c.Payload), resolve(c.Loader), resolve(c.Server)
	if err := validatePE(c.Payload, c.Arch); err != nil {
		fmt.Fprintln(os.Stderr, "rules_wine:", err)
		return 125
	}
	args := append(append([]string{}, c.Args...), extra...)
	for i, arg := range args {
		value, err := convert(arg, c.Runfiles)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 125
		}
		args[i] = value
	}
	env := []string{}
	for _, entry := range os.Environ() {
		// Native same-CPU execution only; never inherit the fork's x86 hybrid opt-in.
		if !strings.HasPrefix(entry, "WINEHYBRIDX86=") {
			env = append(env, entry)
		}
	}
	for key, value := range c.Env {
		if key == "WINEHYBRIDX86" && value != "" {
			fmt.Fprintln(os.Stderr, "rules_wine: CPU translation is unsupported")
			return 125
		}
		converted, err := convert(value, c.Runfiles)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 125
		}
		env = setenv(env, key, converted)
	}
	signals := make(chan os.Signal, 8)
	signal.Notify(signals, cancellationSignals()...)
	defer signal.Stop(signals)
	if c.Backend == "native" {
		if runtime.GOOS != "windows" {
			fmt.Fprintln(os.Stderr, "rules_wine: native backend requires Windows")
			return 125
		}
		return execute(c.Payload, args, env, 0, signals)
	}
	if c.Backend != "wine" || runtime.GOOS != "linux" && runtime.GOOS != "darwin" {
		fmt.Fprintln(os.Stderr, "rules_wine: Wine backend requires Linux or macOS")
		return 125
	}
	if err := validateNative(c.Loader, c.Arch); err != nil {
		fmt.Fprintln(os.Stderr, "rules_wine:", err)
		return 125
	}
	if err := validateNative(c.Server, c.Arch); err != nil {
		fmt.Fprintln(os.Stderr, "rules_wine:", err)
		return 125
	}
	scratchBase := ""
	// macOS's per-user TMPDIR plus Wine's server suffix can exceed sockaddr_un.
	// /tmp is an allowed writable location; MkdirTemp creates a private 0700 dir.
	if runtime.GOOS == "darwin" {
		scratchBase = "/tmp"
	}
	scratch, err := os.MkdirTemp(scratchBase, "rules-wine-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 125
	}
	defer func() {
		if err := os.RemoveAll(scratch); err != nil {
			fmt.Fprintln(os.Stderr, "rules_wine: cleanup:", err)
		}
	}()
	prefix := filepath.Join(scratch, "prefix")
	for key, value := range map[string]string{
		"WINEPREFIX": prefix, "WINEARCH": "win64", "WINELOADER": c.Loader, "WINESERVER": c.Server,
		"WINEDLLOVERRIDES": "mscoree,mshtml,winemenubuilder.exe=", "WINEDEBUG": "-all", "HOME": scratch,
		"XDG_CACHE_HOME": scratch, "TMPDIR": scratch, "TMP": scratch, "TEMP": scratch,
		"LC_ALL": "C.UTF-8", "TZ": "UTC", "DISPLAY": "", "WAYLAND_DISPLAY": "",
		"PATH": filepath.Dir(c.Loader),
	} {
		env = setenv(env, key, value)
	}
	for key, value := range c.RuntimeEnv {
		switch key {
		case "WINEPREFIX", "WINEARCH", "WINELOADER", "WINESERVER", "WINEDLLOVERRIDES", "WINEHYBRIDX86", "HOME", "TMPDIR", "PATH":
			fmt.Fprintln(os.Stderr, "rules_wine: reserved runtime environment", key)
			return 125
		}
		value = strings.ReplaceAll(value, "{loader_dir}", filepath.Dir(c.Loader))
		value = strings.ReplaceAll(value, "{server_dir}", filepath.Dir(c.Server))
		env = setenv(env, key, value)
	}
	// Convert only the test protocol's declared paths. Opaque arguments remain opaque.
	for _, key := range []string{"TEST_TMPDIR", "TEST_UNDECLARED_OUTPUTS_DIR", "TEST_UNDECLARED_OUTPUTS_MANIFEST", "TEST_UNDECLARED_OUTPUTS_ANNOTATIONS_DIR", "XML_OUTPUT_FILE", "TEST_SHARD_STATUS_FILE", "TEST_SRCDIR", "RUNFILES_DIR", "RUNFILES_MANIFEST_FILE"} {
		for _, entry := range env {
			if strings.HasPrefix(entry, key+"=") {
				value := strings.TrimPrefix(entry, key+"=")
				if value != "" {
					env = setenv(env, key, windowsPath(value))
				}
				break
			}
		}
	}
	setupReaper()
	defer func() {
		// Server termination is prefix-scoped. Never use a machine-global pkill.
		quiet := make(chan os.Signal)
		if status := execute(c.Server, []string{"-k"}, env, 5*time.Second, quiet); status != 0 {
			fmt.Fprintln(os.Stderr, "rules_wine: wineserver cleanup status", status)
		}
		execute(c.Server, []string{"-w"}, env, 5*time.Second, quiet)
		reapChildren()
	}()
	bootstrap := filepath.Join(filepath.Dir(c.Loader), "..", "lib", "wine", c.Arch+"-windows", "cmd.exe")
	if _, err := os.Stat(bootstrap); err != nil {
		bootstrap = "cmd.exe"
	}
	if status := execute(c.Loader, []string{bootstrap, "/c", "exit", "0"}, env, 60*time.Second, signals); status != 0 {
		return status
	}
	return execute(c.Loader, append([]string{windowsPath(c.Payload)}, args...), env, 0, signals)
}

func setenv(env []string, key, value string) []string {
	result := make([]string, 0, len(env)+1)
	for _, entry := range env {
		if !strings.HasPrefix(entry, key+"=") {
			result = append(result, entry)
		}
	}
	return append(result, key+"="+value)
}

func main() {
	self, err := filepath.Abs(os.Args[0])
	if err != nil {
		fatal(err)
	}
	config := self + ".json"
	args := os.Args[1:]
	if len(args) >= 2 && args[0] == "--config" {
		config = args[1]
		args = args[2:]
	}
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	data, err := os.ReadFile(config)
	if err != nil {
		fatal(err)
	}
	var c configuration
	if err = json.Unmarshal(data, &c); err != nil {
		fatal(err)
	}
	os.Exit(invoke(c, args))
}
