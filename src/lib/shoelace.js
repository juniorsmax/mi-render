/**
 * Shoelace (Gauss's area) formula for a polygon defined by XZ points.
 * WebXR world space is Y-up, so floor coordinates live in X and Z.
 *
 * @param {Array<{x: number, z: number}>} points
 * @returns {number} area in m²
 */
export function shoelace(points) {
  const n = points.length
  if (n < 3) return 0
  let sum = 0
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n
    sum += points[i].x * points[j].z
    sum -= points[j].x * points[i].z
  }
  return Math.abs(sum) / 2
}
