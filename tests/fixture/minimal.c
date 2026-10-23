/* SDK-free Windows PE fixture; independent of Go's Windows runtime. */
__declspec(dllimport) void *GetStdHandle(unsigned long id);
__declspec(dllimport) int WriteFile(void *file, const void *data, unsigned long size, unsigned long *written, void *overlapped);
__declspec(dllimport) void ExitProcess(unsigned int status);
void mainCRTStartup(void) {
    static const char message[] = "native-windows-payload\r\n";
    unsigned long written = 0;
    int ok = WriteFile(GetStdHandle((unsigned long)-11), message, sizeof(message) - 1, &written, (void *)0);
    ExitProcess(ok && written == sizeof(message) - 1 ? 0 : 7);
}
