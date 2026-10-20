// Accretion: Apple ID (7-day) signing, C interface of AppleIDBridge (Rust, see src/lib.rs).
// Requests and answers are UTF-8 JSON. Every answer is {"ok": true, ...} or {"ok": false, "error": "..."}
// and must be released with accretion_appleid_free. Calls block: never call them on the main thread.

#ifndef ACCRETION_APPLEID_H
#define ACCRETION_APPLEID_H

#ifdef __cplusplus
extern "C" {
#endif

// Called during a request to ask the user something. request_json is
//   {"kind":"two_factor","method":"device"|"sms","phones":[{"id":1,"last_two":"42"}]}
//     answer {"action":"code","code":"123456"} | {"action":"sms","phone_id":1} | {"action":"cancel"}
//   {"kind":"revoke_certificate"}   answer {"action":"yes"} | {"action":"no"}
// Return a malloc'd NUL-terminated string (the library frees it), or NULL to cancel.
typedef char *_Nullable (*AccretionAppleIDPrompt)(void *_Nullable context, const char *_Nonnull request_json);

// {"email","password","anisette":{"url","state_dir"}} -> {"adsid","token"}
char *_Nonnull accretion_appleid_login(const char *_Nonnull request_json,
                                        AccretionAppleIDPrompt _Nonnull prompt,
                                        void *_Nullable context);

// {"op","session":{"adsid","token"},"anisette":{"url","state_dir"},"team_id",...}
//   teams                                    -> {"teams":[{"id","name","type","status"}]}
//   device_status   udid                     -> {"registered","count"}
//   register_device udid, device_name        -> {"registered"}
//   app_ids                                  -> {"identifiers":[...]}
//   certificates                             -> {"certificates":[{"name","serial","status","expires","machine_name"}]}
//   sign  app_path, work_dir, key_pem?, machine_name?, udid?, device_name?, remove_extensions
//         -> {"bundle_id","certificate_new","serial","key_pem","profiles":[{"bundle_id","expires"}]}
char *_Nonnull accretion_appleid_call(const char *_Nonnull request_json,
                                       AccretionAppleIDPrompt _Nonnull prompt,
                                       void *_Nullable context);

// Wipes and frees an answer.
void accretion_appleid_free(char *_Nullable answer);

#ifdef __cplusplus
}
#endif

#endif
