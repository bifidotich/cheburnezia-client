package main

/*
#include "jni_helper.h"
*/
import "C"

import (
	"log"
	"strings"
	"sync"
	"unsafe"

	"org.amnezia.vpn/olcrtc/olcrtcclient"
)

var (
	activeClient *olcrtcclient.Client
	clientMu     sync.Mutex
)

// jniLogWriter forwards the Go standard logger to android.util.Log. Without it
// everything libolcrtc logs would be invisible on device.
type jniLogWriter struct{}

func (jniLogWriter) Write(p []byte) (int, error) {
	msg := strings.TrimRight(string(p), "\n")
	if msg != "" {
		cMsg := C.CString(msg)
		C._nativeLog(cMsg)
		C.free(unsafe.Pointer(cMsg))
	}
	return len(p), nil
}

func init() {
	log.SetFlags(0)
	log.SetOutput(jniLogWriter{})
}

// protectSocket asks the Android layer to exclude fd from the VPN routes.
func protectSocket(fd int) bool {
	return C._protectSocket(C.int(fd)) != 0
}

// notifyState forwards a tunnel state transition to the Kotlin layer.
func notifyState(state string) {
	cState := C.CString(state)
	defer C.free(unsafe.Pointer(cState))
	C._notifyState(cState)
}

//export Java_org_amnezia_vpn_protocol_olcrtc_OlcrtcNative_startTunnel
func Java_org_amnezia_vpn_protocol_olcrtc_OlcrtcNative_startTunnel(
	env *C.JNIEnv,
	thiz C.jobject,
	tunFd C.jint,
	tunMtu C.jint,
	jProvider C.jstring,
	jTransport C.jstring,
	jRoomUrl C.jstring,
	jKey C.jstring,
	jDns C.jstring,
	jProviderToken C.jstring,
) C.jstring {
	clientMu.Lock()
	defer clientMu.Unlock()

	if activeClient != nil {
		activeClient.Stop()
		activeClient = nil
	}

	cfg := olcrtcclient.Config{
		TunFd:         int(tunFd),
		TunMtu:        int(tunMtu),
		Provider:      jstringToString(env, jProvider),
		Transport:     jstringToString(env, jTransport),
		RoomURL:       jstringToString(env, jRoomUrl),
		KeyHex:        jstringToString(env, jKey),
		DNSServer:     jstringToString(env, jDns),
		ProviderToken: jstringToString(env, jProviderToken),
	}

	c, err := olcrtcclient.NewClient(cfg, protectSocket, notifyState)
	if err != nil {
		return stringToJstring(env, err.Error())
	}
	if err := c.Start(); err != nil {
		return stringToJstring(env, err.Error())
	}

	activeClient = c
	// A null return means success; any string is the failure reason.
	return 0
}

//export Java_org_amnezia_vpn_protocol_olcrtc_OlcrtcNative_stopTunnel
func Java_org_amnezia_vpn_protocol_olcrtc_OlcrtcNative_stopTunnel(env *C.JNIEnv, thiz C.jobject) C.jstring {
	clientMu.Lock()
	defer clientMu.Unlock()

	if activeClient == nil {
		return 0
	}

	err := activeClient.Stop()
	activeClient = nil
	if err != nil {
		return stringToJstring(env, err.Error())
	}
	return 0
}

//export Java_org_amnezia_vpn_protocol_olcrtc_OlcrtcNative_restartTunnel
func Java_org_amnezia_vpn_protocol_olcrtc_OlcrtcNative_restartTunnel(env *C.JNIEnv, thiz C.jobject) C.jboolean {
	clientMu.Lock()
	defer clientMu.Unlock()

	if activeClient == nil {
		return C.JNI_FALSE
	}
	activeClient.RequestRestart()
	return C.JNI_TRUE
}

func jstringToString(env *C.JNIEnv, jstr C.jstring) string {
	if jstr == 0 {
		return ""
	}
	var isCopy C.jboolean
	cStr := C._getStringUTFChars(env, jstr, &isCopy)
	if cStr == nil {
		return ""
	}
	defer C._releaseStringUTFChars(env, jstr, cStr)
	return C.GoString(cStr)
}

func stringToJstring(env *C.JNIEnv, s string) C.jstring {
	cStr := C.CString(s)
	defer C.free(unsafe.Pointer(cStr))
	return C._newStringUTF(env, cStr)
}

func main() {}
