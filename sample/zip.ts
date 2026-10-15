// Minimal dependency-free ZIP writer (stored, uncompressed entries). It is
// enough to build a .love file: LÖVE mounts it through PhysFS, which reads both
// stored and deflated entries.

import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";

const CRC_TABLE = (() => {
	const table = new Uint32Array(256);
	for (let n = 0; n < 256; n += 1) {
		let c = n;
		for (let k = 0; k < 8; k += 1) {
			c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		}
		table[n] = c >>> 0;
	}
	return table;
})();

function crc32(bytes: Uint8Array): number {
	let c = 0xffffffff;
	for (let i = 0; i < bytes.length; i += 1) {
		c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
	}
	return (c ^ 0xffffffff) >>> 0;
}

function listFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) {
			listFiles(full, out);
		} else if (entry.isFile()) {
			out.push(full);
		}
	}
	return out;
}

class ByteWriter {
	private parts: Uint8Array[] = [];

	private length = 0;

	get offset(): number {
		return this.length;
	}

	push(bytes: Uint8Array): void {
		this.parts.push(bytes);
		this.length += bytes.length;
	}

	u16(value: number): void {
		const buf = new Uint8Array(2);
		new DataView(buf.buffer).setUint16(0, value, true);
		this.push(buf);
	}

	u32(value: number): void {
		const buf = new Uint8Array(4);
		new DataView(buf.buffer).setUint32(0, value >>> 0, true);
		this.push(buf);
	}

	bytes(): Uint8Array {
		const out = new Uint8Array(this.length);
		let offset = 0;
		for (const part of this.parts) {
			out.set(part, offset);
			offset += part.length;
		}
		return out;
	}
}

// DOS time/date for a fixed 1980-01-01 00:00:00 stamp.
const DOS_TIME = 0;
const DOS_DATE = (1 << 5) | 1;

export function createZip(files: Array<{ name: string; data: Uint8Array }>): Uint8Array {
	const writer = new ByteWriter();
	const encoder = new TextEncoder();
	const central: Array<{ name: Uint8Array; crc: number; size: number; offset: number }> = [];

	for (const file of files) {
		const name = encoder.encode(file.name);
		const crc = crc32(file.data);
		const offset = writer.offset;

		// Local file header.
		writer.u32(0x04034b50);
		writer.u16(20); // version needed
		writer.u16(0); // flags
		writer.u16(0); // method: stored
		writer.u16(DOS_TIME);
		writer.u16(DOS_DATE);
		writer.u32(crc);
		writer.u32(file.data.length);
		writer.u32(file.data.length);
		writer.u16(name.length);
		writer.u16(0); // extra length
		writer.push(name);
		writer.push(file.data);

		central.push({ name, crc, size: file.data.length, offset });
	}

	const centralOffset = writer.offset;

	for (const entry of central) {
		// Central directory header.
		writer.u32(0x02014b50);
		writer.u16(20); // version made by
		writer.u16(20); // version needed
		writer.u16(0); // flags
		writer.u16(0); // method: stored
		writer.u16(DOS_TIME);
		writer.u16(DOS_DATE);
		writer.u32(entry.crc);
		writer.u32(entry.size);
		writer.u32(entry.size);
		writer.u16(entry.name.length);
		writer.u16(0); // extra length
		writer.u16(0); // comment length
		writer.u16(0); // disk number start
		writer.u16(0); // internal attributes
		writer.u32(0o100644 << 16); // external attributes
		writer.u32(entry.offset);
		writer.push(entry.name);
	}

	const centralSize = writer.offset - centralOffset;

	// End of central directory.
	writer.u32(0x06054b50);
	writer.u16(0); // disk number
	writer.u16(0); // disk with central directory
	writer.u16(central.length);
	writer.u16(central.length);
	writer.u32(centralSize);
	writer.u32(centralOffset);
	writer.u16(0); // comment length

	return writer.bytes();
}

export function packLove(gameDir: string, outFile: string): { files: number; size: number } {
	const names = listFiles(gameDir).sort();
	const files = names.map((full) => ({
		name: relative(gameDir, full).split(sep).join("/"),
		data: readFileSync(full),
	}));

	const zip = createZip(files);
	writeFileSync(outFile, zip);
	return { files: files.length, size: zip.length };
}
