#ifndef ROOM_CEF_HELPER_H_
#define ROOM_CEF_HELPER_H_

#ifdef __cplusplus
extern "C" {
#endif

/// Entry point of every `Room Helper*.app`: enters the sandbox, loads the CEF
/// framework and runs the sub-process (renderer, GPU, utility, ...).
int RoomCEFHelperMain(int argc, char* _Nonnull argv[_Nonnull]);

#ifdef __cplusplus
}
#endif

#endif  // ROOM_CEF_HELPER_H_
