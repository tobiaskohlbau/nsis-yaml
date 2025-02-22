#include <windows.h>
#include <pluginapi.h>
#include <stdint.h>

HINSTANCE g_hInstance;
HWND g_hwndParent;

extern int32_t cWriteYaml(char *location, char *path, char *value);

char *convertToUTF8(TCHAR *input) {
    char required_size = WideCharToMultiByte(CP_UTF8, 0, input, -1, NULL, 0, NULL, NULL);
    if (required_size == 0) {
      return NULL;
    }

    char *buffer = GlobalAlloc(GPTR, required_size * sizeof(char));
    if (buffer == NULL) {
      return NULL;
    }

    if (WideCharToMultiByte(CP_UTF8, 0, input, -1, buffer, required_size, NULL, NULL) == 0) {
      return NULL;
    }

    return buffer;
}

void __declspec(dllexport) write(HWND hwndParent, int string_size, 
                                      LPTSTR variables, stack_t **stacktop,
                                      extra_parameters *extra, ...)
{
  EXDLL_INIT();
  g_hwndParent = hwndParent;

  {
    TCHAR filename[1024];
    TCHAR path[1024];
    TCHAR value[1024];
    popstring(filename);
    popstring(path);
    popstring(value);

    char *filenameUTF8 = convertToUTF8(filename);
    char *pathUTF8 = convertToUTF8(path);
    char *valueUTF8 = convertToUTF8(value);

    if (filenameUTF8 == NULL || pathUTF8 == NULL || valueUTF8 == NULL) {
      pushstring(TEXT("error"));
      goto exit;
    }
    
    if (cWriteYaml(filenameUTF8, pathUTF8, valueUTF8) != 0) {
      pushstring(TEXT("error"));
      goto exit;
    }

exit:
    GlobalFree(filenameUTF8);
    GlobalFree(pathUTF8);
    GlobalFree(valueUTF8);
  }
}


BOOL WINAPI DllMain(HINSTANCE hInst, ULONG ul_reason_for_call, LPVOID lpReserved)
{
  g_hInstance = hInst;
  return TRUE;
}
