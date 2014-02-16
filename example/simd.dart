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
		average2x2_simd(img, avg_simd);
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
	var buf = input.buffer;
	var w = input.width;
	var h = input.height;
	var halfW = w ~/ 2;
	var quadW = w ~/ 4;
	// var halfH = h ~/ 2;
	var rowByteStride = w * 4;
	for (int y=0; y<w; y += 2) {
		var firstRow = new Int32x4List.view(buf, y*rowByteStride);
		var secondRow = new Int32x4List.view(buf, (y+1)*rowByteStride);
		var outRow = (y ~/ 2) * halfW;
		for (int x=0; x<quadW; x++) {
			var first = firstRow[x];
			var second = secondRow[x];
			var tl0 = signExtendLane(first, 0);
			var tr0 = signExtendLane(first, 1);
			var tl1 = signExtendLane(first, 2);
			var tr1 = signExtendLane(first, 3);

			var bl0 = signExtendLane(second, 0);
			var br0 = signExtendLane(second, 1);
			var bl1 = signExtendLane(second, 2);
			var br1 = signExtendLane(second, 3);

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
 * Sign extend specified lane to a single Int32x4
 */
Int32x4 signExtendLane(Int32x4 value, int laneIndex) {
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
 * right shift each lane
 */
Int32x4 shiftRightPerLane(Int32x4 value, int shift) {
	return new Int32x4(value.x >> shift, value.y >> shift, value.z >> shift, value.w >> shift);
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
