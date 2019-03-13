#!/usr/bin/env bash
WORKDIR="$( cd "$(dirname "$0")" ; pwd -P )"

# path of connectme repo on our machine
CONNECTME_WORKDIR=${WORKDIR}/../..

INDY_BUILD_DIR=/tmp/android_build
INDY_SOURCE_DIR=/tmp/indy-sdk
VCX_WORKDIR=${INDY_SOURCE_DIR}/vcx

download_and_unzip_deps(){
	rm -rf indy-android-dependencies
	git clone https://github.com/sovrin-foundation/indy-android-dependencies
    git checkout v1.1.1
	pushd indy-android-dependencies/prebuilt/ && find . -name "*.zip" | xargs -P 5 -I FILENAME sh -c 'unzip -o -d "$(dirname "FILENAME")" "FILENAME"'
	popd
	mv indy-android-dependencies/prebuilt dependencies
}


generate_flags(){
	if [ -z $1 ]; then
		echo "please provide the arch e.g arm, x86 or arm64"
	fi
	if [ $1 == "arm" ]; then
		export ARCH="arm"
		export TRIPLET="arm-linux-androideabi"
		export PLATFORM="16"
		export ABI="armeabi-v7a"
	fi

	if [ $1 == "x86" ]; then
		export ARCH="x86"
		export TRIPLET="i686-linux-android"
		export PLATFORM="16"
		export ABI="x86"
	fi

	if [ $1 == "arm64" ]; then
		export ARCH="arm64"
		export TRIPLET="aarch64-linux-android"
		export PLATFORM="21"
		export ABI="arm64-v8a"
	fi
}

checkout_indy(){
    mkdir -p $INDY_SOURCE_DIR
    pushd $INDY_SOURCE_DIR
        git clone https://github.com/hyperledger/indy-sdk $INDY_SOURCE_DIR
		# git -C $INDY_SOURCE_DIR pull || git clone https://github.com/hyperledger/indy-sdk $INDY_SOURCE_DIR
		git checkout 95a38a5a7ae9767323afbcca18a96189b6d448d1
    popd
}

build_indy(){
	generate_flags $1
	pushd $INDY_SOURCE_DIR/libindy
        bash ${INDY_SOURCE_DIR}/libindy/android.build.sh -d ${ARCH}
    popd

}

build_libnullpay(){
	generate_flags $1
	export INDY_DIR=${INDY_BUILD_DIR}/libindy_${ARCH}/lib
	pushd $INDY_SOURCE_DIR/libnullpay
        bash ${INDY_SOURCE_DIR}/libnullpay/android.build.sh -d ${ARCH}
	popd

}


build_vcx(){
	generate_flags $1
	pushd ${VCX_WORKDIR}/libvcx/build_scripts/android/vcx
		cp -rf ${INDY_BUILD_DIR}/libindy_${ARCH} .
		cp -rf ${INDY_BUILD_DIR}/libnullpay_${ARCH} .
        export LIBINDY_DIR=${INDY_BUILD_DIR}/libindy_${ARCH}
		./build.nondocker.sh ${ARCH} ${PLATFORM} ${TRIPLET} ${INDY_BUILD_DIR}/openssl_${ARCH} ${INDY_BUILD_DIR}/libsodium_${ARCH} ${INDY_BUILD_DIR}/libzmq_${ARCH}
	popd
}

build_wrapper(){
	mkdir -p ${VCX_WORKDIR}/wrappers/java/vcx/src/main/jniLibs/arm
	# export ANDROID_HOME=/home/sami/Android/Sdk
	# mkdir -p ${VCX_WORKDIR}/wrappers/java/vcx/src/main/jniLibs/x86
	cp -v ${VCX_WORKDIR}/libvcx/build_scripts/android/vcx/libvcx_arm/libvcx.so ${VCX_WORKDIR}/wrappers/java/vcx/src/main/jniLibs/armeabi-v7a
	# cp -v ${VCX_WORKDIR}/libvcx/build_scripts/android/vcx/libvcx_x86/libvcx.so ${VCX_WORKDIR}/wrappers/java/vcx/src/main/jniLibs/x86
	pushd ${VCX_WORKDIR}/wrappers/java
		./gradlew clean assemble --project-dir=android
	popd
}

copy_wrapper(){
	cp -v ${VCX_WORKDIR}/wrappers/java/vcx/build/outputs/aar/vcx-release.aar ${CONNECTME_WORKDIR}/android/app/libs
}

build_wrapper_and_update_gradle_files(){
	AAR=$(build_wrapper | perl -nle 'print $& if m{(?<=vcx-1.0.0-)(.*)(?=.aar)}' | head -1 | awk '{print $1}' )
	echo ${AAR}
	REPLACE=$(cat ${CONNECTME_WORKDIR}/android/app/build.gradle | perl -nle "print $& if m{(?<=vcx:1.0.0-)(.*)(?=')}")
	echo " ${REPLACE} will be replaced with :: ${AAR} in build.gradle"
	sleep 10
	pushd ${CONNECTME_WORKDIR}/android/app/
		sed -i '.original' "s/${REPLACE}/${AAR}/g" build.gradle
		rm build.gradle.original
	popd
}

uninstall_app(){
		adb uninstall me.connect
		sleep 10
}
delete_existing_wallet(){
	adb shell rm -rf /sdcard/.indy_client
}
run_app(){
	#Run Connect.me in emulator
	pushd ${CONNECTME_WORKDIR}
		react-native bundle --platform android --dev true --entry-file index.js --bundle-output android/app/src/main/assets/index.android.bundle --assets-dest android/app/src/main/res
		pushd android
			../gradlew clean installDebug --stacktrace && \
			adb -s emulator-5554 reverse tcp:8081 tcp:8081 && \
			adb shell pm grant me.connect android.permission.SYSTEM_ALERT_WINDOW && \
			adb shell pm grant me.connect android.permission.WRITE_EXTERNAL_STORAGE && \
			adb shell pm grant me.connect android.permission.READ_EXTERNAL_STORAGE && \
			adb -s emulator-5554 shell am start -n me.connect/me.connect.MainActivity


		popd
	popd
}




checkout_indy
build_indy arm
build_libnullpay arm
build_vcx arm

# build_indy arm64
# build_libnullpay arm64
# build_vcx arm64

# build_indy x86
# build_libnullpay x86
# build_vcx x86

build_wrapper
# pushd $CONNECTME_WORKDIR