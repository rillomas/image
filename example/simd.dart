import "dart:io";
import "dart:typed_data";
import "package:image/image.dart";

void main() {
	var imgFile = new File("res/Lenna.png");
	var img = decodePng(imgFile.readAsBytesSync());
	print("Input Image size: ${img.width}x${img.height} buffer length: ${img.length}");

	var halfW = img.width ~/ 2;
	var halfH = img.height ~/ 2;
	var avg_normal = new Image(halfW, halfH);
	var iteration = 1;
	var watch = new Stopwatch()..start();
	for (int i=0; i<iteration; i++) {
		average2x2(img, avg_normal);
	}
	watch.stop();
	var ms = watch.elapsedMilliseconds;
	var msPerRun = ms / iteration;
	print("Normal Elapsed: $ms Average: $msPerRun");

	var avg_simd = new Image(halfW, halfH);
	watch..reset()..start();
	for (int i=0; i<iteration; i++) {
		average2x2_simd_2(img, avg_simd);
		// average2x2_simd(img, avg_simd);
	}
	watch.stop();
	ms = watch.elapsedMilliseconds;
	msPerRun = ms / iteration;
	print("SIMD Elapsed: $ms Average: $msPerRun");

	for (int i=0; i<avg_normal.length; i++) {
		var n = avg_normal[i];
		var s = avg_simd[i];
		if (n != s) {
			print("Mismatch at $i! normal: ${n.toRadixString(16)} simd: ${s.toRadixString(16)}");
		}
	}

	writeImageToPng(avg_normal, "Lenna_avg_normal.png");
	writeImageToPng(avg_simd, "Lenna_avg_simd.png");

}

void writeImageToPng(Image img, String path) {
	var imgFile = new File(path);
	imgFile.writeAsBytesSync(encodePng(img));
}

/**
 * 2x2 average filter (Image is shrinked to 1/16)
 */
void average2x2(Image input, Image output) {
	var w = input.width;
	var h = input.height;
	for (int y=0; y<h; y += 2) {
		var firstRow = y * w;
		var secondRow = (y+1) * w;
		var outRow = (y ~/ 2) * output.width;
		for (int x=0; x<w; x += 2) {
			// get four pixels and average them
			var topLeftIdx = firstRow + x;
			var topRightIdx = topLeftIdx + 1;
			var btmLeftIdx = secondRow + x;
			var btmRightIdx = btmLeftIdx + 1;
			var tl = input[topLeftIdx];
			var tr = input[topRightIdx];
			var bl = input[btmLeftIdx];
			var br = input[btmRightIdx];

			var tlr = getRed(tl);
			var tlg = getGreen(tl);
			var tlb = getBlue(tl);
			var tla = getAlpha(tl);

			var trr = getRed(tr);
			var trg = getGreen(tr);
			var trb = getBlue(tr);
			var tra = getAlpha(tr);

			var blr = getRed(bl);
			var blg = getGreen(bl);
			var blb = getBlue(bl);
			var bla = getAlpha(bl);

			var brr = getRed(br);
			var brg = getGreen(br);
			var brb = getBlue(br);
			var bra = getAlpha(br);

			var avgr = (tlr + trr + blr + brr) >> 2;
			var avgg = (tlg + trg + blg + brg) >> 2;
			var avgb = (tlb + trb + blb + brb) >> 2;
			var avga = (tla + tra + bla + bra) >> 2;

			var avg = getColor(avgr, avgg, avgb, avga);
			var outIdx = outRow + (x ~/ 2);
			output[outIdx] = avg;
		}
	}
}

/**
 * SIMD version of the 2x2 average filter
 */
void average2x2_simd(Image input, Image output) {
	var w = input.width;
	var h = input.height;
	var halfW = w ~/ 2;
	var quadW = w ~/ 4;
	// var halfH = h ~/ 2;
	var rowByteStride = w * 4;
	var buf = input.buffer;
	for (int y=0; y<w; y += 2) {
		var firstRow = new Int32x4List.view(buf, y*rowByteStride);
		var secondRow = new Int32x4List.view(buf, (y+1)*rowByteStride);
		var outRow = (y ~/ 2) * halfW;
		for (int x=0; x<quadW; x++) {
			var first = firstRow[x];
			var second = secondRow[x];
			var tl0 = signExtendTo32Bit(first, 0);
			var tr0 = signExtendTo32Bit(first, 1);
			var tl1 = signExtendTo32Bit(first, 2);
			var tr1 = signExtendTo32Bit(first, 3);

			var bl0 = signExtendTo32Bit(second, 0);
			var br0 = signExtendTo32Bit(second, 1);
			var bl1 = signExtendTo32Bit(second, 2);
			var br1 = signExtendTo32Bit(second, 3);

			var vsum0 = tl0 + tr0 + bl0 + br0;
			var vsum1 = tl1 + tr1 + bl1 + br1;
			var vavg0 = shiftRightPerLane(vsum0, 2);
			var vavg1 = shiftRightPerLane(vsum1, 2);
			var avg0 = packLaneByte(vavg0);
			var avg1 = packLaneByte(vavg1);

			var outIdx = outRow+(x*2);
			output[outIdx] = avg0;
			output[outIdx+1] = avg1;
		}
	}
}

/**
 * another SIMD version of the 2x2 average filter
 */
void average2x2_simd_2(Image input, Image output) {
	var w = input.width;
	var h = input.height;
	var halfW = w ~/ 2;
	var quadW = w ~/ 4;
	// var halfH = h ~/ 2;
	var rowByteStride = w * 4;
	var buf = input.buffer;
	for (int y=0; y<w; y += 2) {
		var firstRow = new Int32x4List.view(buf, y*rowByteStride);
		var secondRow = new Int32x4List.view(buf, (y+1)*rowByteStride);
		var outRow = (y ~/ 2) * halfW;
		for (int x=0; x<quadW; x++) {
			var first = firstRow[x];
			var second = secondRow[x];
			var t0 = signExtendTo16Bit(first, true);
			var t1 = signExtendTo16Bit(first, false);

			var b0 = signExtendTo16Bit(second, true);
			var b1 = signExtendTo16Bit(second, false);

			var vsum0 = t0 + b0;
			var vsum1 = t1 + b1;
			var sum0_ab = vsum0.x + vsum0.z;
			var sum0_gr = vsum0.y + vsum0.w;
			var avg0_ab = shiftRightPer16Bit(sum0_ab, 2);
			var avg0_gr = shiftRightPer16Bit(sum0_gr, 2);
			var avg0 = pack(avg0_ab, avg0_gr);

			var sum1_ab = vsum1.x + vsum1.z;
			var sum1_gr = vsum1.y + vsum1.w;
			var avg1_ab = shiftRightPer16Bit(sum1_ab, 2);
			var avg1_gr = shiftRightPer16Bit(sum1_gr, 2);
			var avg1 = pack(avg1_ab, avg1_gr);
			var outIdx = outRow+(x*2);
			output[outIdx] = avg0;
			output[outIdx+1] = avg1;
		}
	}
}

/**
 * Sign extend specified lane to four 32bit values
 */
Int32x4 signExtendTo32Bit(Int32x4 value, int laneIndex) {
	int val = 0;
	switch (laneIndex) {
		case 0:
			val = value.x;
			break;
		case 1:
			val = value.y; 
			break;
		case 2:
			val = value.z; 
			break;
		case 3:
			val = value.w; 
			break;
	}
	return new Int32x4((val >> 24 & 0xff), (val >> 16 & 0xff), (val >> 8 & 0xff), val & 0xff);
}

/**
 * Sign extend half of an Int32x4 to eight 16bit values
 */
Int32x4 signExtendTo16Bit(Int32x4 value, bool firstHalf) {
	int left = 0;
	int right = 0;
	if (firstHalf) {
		left = value.x;
		right = value.y;
	} else {
		left = value.z;
		right = value.w;
	}

	var hiMask = 0x00ff0000;
	var loMask = 0x000000ff;

	var x = ((left >> 8) & hiMask) | ((left >> 16) & loMask);
	var y = ((left << 8) & hiMask) | (left & loMask);
	var z = ((right >> 8) & hiMask) | ((right >> 16) & loMask);
	var w = ((right << 8) & hiMask) | (right & loMask);
	return new Int32x4(x,y,z,w);
}

/**
 * right shift each lane
 */
Int32x4 shiftRightPerLane(Int32x4 value, int shift) {
	return new Int32x4(value.x >> shift, value.y >> shift, value.z >> shift, value.w >> shift);
}

/**
 * right shift per 16bit
 */
int shiftRightPer16Bit(int value, int shift) {
	var shifted = value >> shift;
	var hiMask = 0xffff0000;
	var loMask = 0x0000ffff;
	return (shifted & hiMask) | (shifted & loMask);
}

/**
 * pack each lane's byte to a 32bit int
 */
int packLaneByte(Int32x4 value) {
	var x = (value.x & 0xff) << 24;
	var y = (value.y & 0xff) << 16;
	var z = (value.z & 0xff) << 8;
	var w = value.w & 0xff;
	return x | y | z | w;
}

/**
 * pack two 32bit integers to a single 32bit integer
 */
int pack(int left, int right) {
	var hiMask = 0x00ff0000;
	var loMask = 0xff;
	var x = (left & hiMask) << 8;
	var y = (left & loMask) << 16;
	var z = (right & hiMask) >> 8;
	var w = (right & loMask);
	return x | y | z | w;
}