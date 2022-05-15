#!/bin/sh

JOB_DIR=work
cd "${WORKSPACE}/${JOB_DIR}" || exit

KERNCONF=${KERNCONF:-GENERIC}
if [ "${KERNCONF}" = "GENERIC" ]; then
	IMG_NAME=disk-test.img
else
	IMG_NAME=disk-test-${KERNCONF}.img
fi
zstd -T0 -fd -q --no-progress "${IMG_NAME}.zst"
TEST_BASE=${WORKSPACE}/.cirrus-ci/scripts/test

TIMEOUT=2592000

: ${VM_CPU_COUNT:=2}
: ${VM_MEM_SIZE:=6144m}

METADIR=meta
METAOUTDIR=meta-out

# prepare meta disk to pass information to testvm
rm -fr ${METADIR}
mkdir ${METADIR}
cp ${META} ${METADIR}/run.sh
for i in ${USE_TEST_SUBR}; do
	cp ${TEST_BASE}/subr/${i} ${METADIR}/
done
touch ${METADIR}/auto-shutdown
sh -ex ${TEST_BASE}/create-meta.sh

if [ "${USE_QEMU}" = 1 ]; then
	# run test VM image with qemu
	set +e

	: ${QEMU_DEVICES:="-device virtio-blk,drive=hd0 -device virtio-blk,drive=hd1"}
	/usr/bin/qemu-system-${QEMU_ARCH} --accel help
	timeout -k 60 ${TIMEOUT} /usr/bin/qemu-system-${QEMU_ARCH} \
		-machine ${QEMU_MACHINE} \
		-smp ${VM_CPU_COUNT} \
		-m ${VM_MEM_SIZE} \
		-nographic \
		-no-reboot \
		${QEMU_EXTRA_PARAM} \
		-drive if=none,file=${IMG_NAME},format=raw,id=hd0 \
		-drive if=none,file=meta.tar,format=raw,id=hd1 \
		${QEMU_DEVICES}
	rc=$?
	echo "qemu return code = $rc"
fi

# extract test result
sh -ex ${TEST_BASE}/extract-meta.sh
rm -f test-report.*
mkdir -p ${WORKSPACE}/artifact/
mv ${METAOUTDIR}/test-report.* ${WORKSPACE}/artifact/

# Turn known test failures into xfails.
report="test-report.xml"
if [ -e ${JOB_DIR}/xfail-list -a -e "${report}" ]; then
	while IFS=":" read classname name; do
		xpath="/testsuite/testcase[@classname=\"${classname}\"][@name=\"${name}\"]"
		if ! xml sel -Q -t -c "${xpath}/*[self::error or self::failure]" "${report}"; then
			if ! xml sel -Q -t -c "${xpath}" "${report}"; then
				echo "Testcase ${classname}:${name} vanished"
			else
				echo "Testcase ${classname}:${name} unexpectedly succeeded"
			fi
		else
			xml ed -P -L -r "${xpath}/*[self::error or self::failure]" -v skipped "${report}"
		fi
	done < ${JOB_DIR}/xfail-list
fi

rm -f ${IMG_NAME}
