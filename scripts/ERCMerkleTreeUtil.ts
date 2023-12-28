export function compareBytes(a: Uint8Array, b: Uint8Array): number {
    const n = Math.min(a.length, b.length);

    for (let i = 0; i < n; i++) {
        if (a[i] !== b[i]) {
            return a[i]! - b[i]!;
        }
    }

    return a.length - b.length;
}

export function equalsBytes(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) {
        return false;
    }
    for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) {
            return false;
        }
    }
    return true;
}

export function checkBounds(array: unknown[], index: number) {
    if (index < 0 || index >= array.length) {
        throw new Error('Index out of bounds');
    }
}

export function throwError(message?: string): never {
    throw new Error(message);
}

export function concatBytes(...arrays: Uint8Array[]) {
    if (!arrays.every((a) => a instanceof Uint8Array))
        throw new Error('Uint8Array list expected');
    if (arrays.length === 1)
        return arrays[0];
    const length = arrays.reduce((a, arr) => a + arr.length, 0);
    const result = new Uint8Array(length);
    for (let i = 0, pad = 0; i < arrays.length; i++) {
        const arr = arrays[i];
        result.set(arr, pad);
        pad += arr.length;
    }
    return result;
}
