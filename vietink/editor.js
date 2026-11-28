const storageKey = 'vietink-trial-2026-v1';
const paperWidth = 900;
const paperKinds = new Set(['lines', 'grid', 'dots', 'blank']);
const shapeKinds = new Set(['line', 'rect', 'ellipse']);
const brushKinds = new Set(['pen', 'fountain', 'pencil', 'marker']);
const tools = new Set([...brushKinds, ...shapeKinds, 'eraser', 'select', 'laser', 'pan']);
const pointEpsilon = 1e-8;
export const eraserSizes = Object.freeze({ min: 6, max: 72, initial: 24 });

const clamp = (value, minimum, maximum) => Math.min(maximum, Math.max(minimum, value));
const add = (a, b) => ({ x: a.x + b.x, y: a.y + b.y });
const subtract = (a, b) => ({ x: a.x - b.x, y: a.y - b.y });
const scale = (point, factor) => ({ x: point.x * factor, y: point.y * factor });
const dot = (a, b) => a.x * b.x + a.y * b.y;
const length = point => Math.hypot(point.x, point.y);
const lerp = (a, b, t) => add(a, scale(subtract(b, a), t));

function blankNote() {
  return { title: 'Ghi chú mới', paper: 'lines', height: 3200, marks: [] };
}

function rectangle(a, b) {
  return {
    left: Math.min(a.x, b.x), right: Math.max(a.x, b.x),
    top: Math.min(a.y, b.y), bottom: Math.max(a.y, b.y),
  };
}

function inflate(rect, margin) {
  return {
    left: rect.left - margin, right: rect.right + margin,
    top: rect.top - margin, bottom: rect.bottom + margin,
  };
}

function overlaps(a, b) {
  return a.left <= b.right && a.right >= b.left && a.top <= b.bottom && a.bottom >= b.top;
}

function contains(rect, point) {
  return overlaps(rect, rectangle(point, point));
}

function distanceToSegment(point, start, end) {
  const delta = subtract(end, start);
  const t = clamp(dot(subtract(point, start), delta) / (dot(delta, delta) || 1), 0, 1);
  return length(subtract(point, lerp(start, end, t)));
}

function ruleWidth(mark) {
  return mark.w * (mark.type === 'marker' ? 3 : mark.type === 'pencil' ? 0.85 : 1);
}

function dashPattern(mark) {
  return [Math.max(4, mark.w * 3), Math.max(3, mark.w * 2)];
}

function inkLerp(a, b, t) {
  const point = lerp(a, b, t);
  if (a.weight !== undefined && b.weight !== undefined) {
    point.weight = a.weight + (b.weight - a.weight) * t;
  }
  return point;
}

function pointsForShape(mark) {
  const start = mark.pts[0];
  const end = mark.pts.at(-1);
  if (mark.type === 'line') return [start, end];
  if (mark.type === 'rect') {
    return [start, { x: end.x, y: start.y }, end, { x: start.x, y: end.y }, start];
  }
  const center = lerp(start, end, 0.5);
  const rx = Math.abs(start.x - end.x) / 2;
  const ry = Math.abs(start.y - end.y) / 2;
  const steps = clamp(Math.ceil(Math.PI * (rx + ry) / 5), 24, 160);
  return Array.from({ length: steps + 1 }, (_, i) => {
    const theta = i / steps * 2 * Math.PI;
    return { x: center.x + Math.cos(theta) * rx, y: center.y + Math.sin(theta) * ry };
  });
}

// Quadratic reconstruction softens pointer-message corners. Saving its sampled
// outline lets the eraser split a curve without rebuilding or warping the ends.
function traceSmooth(points, curve, line, interpolate = lerp) {
  let last = points[0];
  for (let index = 1; index < points.length - 1; index++) {
    const control = points[index];
    const end = interpolate(control, points[index + 1], 0.5);
    curve(last, control, end);
    last = end;
  }
  line(last, points.at(-1));
}

function smoothPoints(points, interpolate = lerp) {
  if (points.length < 3) return points.slice();
  const result = [points[0]];
  traceSmooth(
    points,
    (start, control, end) => {
      const deviation = distanceToSegment(control, start, end);
      const steps = clamp(Math.ceil(Math.sqrt(deviation / 0.35)), 1, 20);
      for (let step = 1; step <= steps; step++) {
        const t = step / steps;
        result.push(interpolate(
          interpolate(start, control, t),
          interpolate(control, end, t),
          t,
        ));
      }
    },
    (_, end) => result.push(end),
    interpolate,
  );
  return result;
}

// A slanted nib makes a wider mark across its edge than along it. Stylus
// pressure adds variation, and recording the width keeps erased pieces stable.
function fountainPoints(samples) {
  const weighted = samples.map((sample, index) => {
    const before = samples[Math.max(0, index - 1)];
    const after = samples[Math.min(samples.length - 1, index + 1)];
    const direction = subtract(after, before);
    const span = length(direction);
    const across = span > pointEpsilon
      ? Math.min(1, Math.abs(0.5 * direction.x + 0.866 * direction.y) / span)
      : 0.7;
    const pressure = sample.pressure ?? 0.72;
    return {
      x: sample.x,
      y: sample.y,
      weight: (0.25 + 0.75 * across) * (0.45 + 0.55 * pressure),
    };
  });
  return smoothPoints(weighted, inkLerp);
}

function addInkDisk(path, point, radius) {
  path.moveTo(point.x + radius, point.y);
  path.arc(point.x, point.y, radius, 0, 2 * Math.PI);
  path.closePath();
}

function fountainPath(points, mark) {
  const path = new Path2D();
  const radius = (point) => mark.w * (point.weight ?? 0.7) / 2;
  if (points.length === 1) {
    addInkDisk(path, points[0], radius(points[0]));
    return path;
  }
  const [dash, gap] = dashPattern(mark);
  const cycle = dash + gap;
  const position = mark.phase || 0;
  let phase = ((position % cycle) + cycle) % cycle;

  for (let index = 1; index < points.length; index++) {
    const a = points[index - 1];
    const b = points[index];
    const delta = subtract(b, a);
    const span = length(delta);
    if (span < pointEpsilon) continue;
    const normal = { x: -delta.y / span, y: delta.x / span };
    let start = 0;
    while (start < span - pointEpsilon) {
      const painted = !mark.dashed || phase < dash - pointEpsilon;
      const remaining = painted ? dash - phase : cycle - phase;
      const end = mark.dashed ? Math.min(span, start + remaining) : span;
      if (painted) {
        const first = inkLerp(a, b, start / span);
        const last = inkLerp(a, b, end / span);
        const firstRadius = radius(first);
        const lastRadius = radius(last);
        path.moveTo(first.x + normal.x * firstRadius, first.y + normal.y * firstRadius);
        path.lineTo(first.x - normal.x * firstRadius, first.y - normal.y * firstRadius);
        path.lineTo(last.x - normal.x * lastRadius, last.y - normal.y * lastRadius);
        path.lineTo(last.x + normal.x * lastRadius, last.y + normal.y * lastRadius);
        path.closePath();
        addInkDisk(path, first, firstRadius);
        addInkDisk(path, last, lastRadius);
      }
      phase += end - start;
      if (phase >= cycle - pointEpsilon) phase = 0;
      start = end;
    }
  }
  return path;
}

function fountainPressure(event, fallback = 0.72) {
  return event.pointerType === 'pen' && event.pressure > 0
    ? clamp(event.pressure, 0, 1)
    : fallback;
}

function brushAlpha(type) {
  if (type === 'marker') return 0.28;
  if (type === 'pencil') return 0.82;
  return 1;
}

export function paintBrushPreview(canvas, mark) {
  const context = canvas.getContext('2d');
  context.setTransform(2, 0, 0, 2, 0, 0);
  const width = canvas.width / 2;
  const height = canvas.height / 2;
  context.clearRect(0, 0, width, height);
  const lineWidth = ruleWidth(mark);
  const inset = Math.max(22, lineWidth / 2 + 5);
  const amplitude = clamp((height - lineWidth) / 2 - 2, 0, 10);
  const points = Array.from({ length: 49 }, (_, index) => {
    const t = index / 48;
    return {
      x: inset + t * (width - 2 * inset),
      y: height / 2 - amplitude * Math.sin(t * 3 * Math.PI),
    };
  });
  context.globalAlpha = brushAlpha(mark.type);
  if (mark.type === 'fountain') {
    context.fillStyle = mark.color;
    context.fill(fountainPath(fountainPoints(points), mark));
  } else {
    context.beginPath();
    context.lineWidth = lineWidth;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.strokeStyle = mark.color;
    context.setLineDash(mark.dashed ? dashPattern(mark) : []);
    context.moveTo(points[0].x, points[0].y);
    for (const point of points.slice(1)) context.lineTo(point.x, point.y);
    context.stroke();
  }
  context.globalAlpha = 1;
}

function loadNote() {
  try {
    const record = JSON.parse(localStorage.getItem(storageKey));
    if (!record?.doc || !Array.isArray(record.doc.marks)) return null;
    const document = record.doc;
    const marks = document.marks.flatMap(mark => {
      if (!brushKinds.has(mark?.type) && !shapeKinds.has(mark?.type)) return [];
      if (!Array.isArray(mark.pts)) return [];
      const points = mark.pts.filter(p => Number.isFinite(p?.x) && Number.isFinite(p?.y));
      if (points.length === 0) return [];
      const fountain = mark.type === 'fountain' ||
        (mark.type === 'pen' && (mark.nib === 'fountain' || points.some(point => Number.isFinite(point.weight))));
      const storedPoints = fountain
        ? points.map(({ x, y, weight }) => ({
          x, y, weight: Number.isFinite(weight) ? clamp(weight, 0.1, 1) : 0.7,
        }))
        : shapeKinds.has(mark.type) || mark.smooth ? points : smoothPoints(points);
      return [{
        type: fountain ? 'fountain' : mark.type,
        color: typeof mark.color === 'string' ? mark.color : '#26364c',
        w: Number.isFinite(mark.w) ? clamp(mark.w, 0.2, 60) : 3,
        pts: storedPoints,
        smooth: true,
        dashed: Boolean(mark.dashed),
        phase: Number.isFinite(mark.phase) ? mark.phase : 0,
      }];
    });
    const camera = record.cam;
    return {
      note: {
        title: typeof document.title === 'string' ? document.title : 'Ghi chú mới',
        paper: paperKinds.has(document.paper) ? document.paper : 'lines',
        height: Number.isFinite(document.height) ? Math.max(600, document.height) : 3200,
        marks,
      },
      camera: Number.isFinite(camera?.x) && Number.isFinite(camera?.y) && Number.isFinite(camera?.z)
        ? { x: camera.x, y: camera.y, z: clamp(camera.z, 0.22, 4) }
        : null,
    };
  } catch {
    return null;
  }
}

function segmentRangeInRect(start, delta, rect) {
  let from = 0;
  let to = 1;
  for (const [position, speed, minimum, maximum] of [
    [start.x, delta.x, rect.left, rect.right],
    [start.y, delta.y, rect.top, rect.bottom],
  ]) {
    if (Math.abs(speed) < pointEpsilon) {
      if (position < minimum || position > maximum) return null;
      continue;
    }
    const first = (minimum - position) / speed;
    const last = (maximum - position) / speed;
    from = Math.max(from, Math.min(first, last));
    to = Math.min(to, Math.max(first, last));
    if (to < from) return null;
  }
  return [from, to];
}

function segmentRangeInDisk(start, delta, center, radius) {
  const offset = subtract(start, center);
  const quadratic = dot(delta, delta);
  if (quadratic < pointEpsilon) {
    return dot(offset, offset) <= radius * radius ? [0, 1] : null;
  }
  const linear = 2 * dot(offset, delta);
  const constant = dot(offset, offset) - radius * radius;
  const discriminant = linear * linear - 4 * quadratic * constant;
  if (discriminant <= 0) return null;
  const signedRoot = Math.sqrt(discriminant) * (linear < 0 ? -1 : 1);
  const stable = -0.5 * (linear + signedRoot);
  const first = stable / quadratic;
  const second = constant / stable;
  const from = Math.max(0, Math.min(first, second));
  const to = Math.min(1, Math.max(first, second));
  return to > from ? [from, to] : null;
}

// The sweep is the union of a rectangle and the two round end caps. It is
// convex, so any surviving intersection times can be joined into one range.
function segmentRangeInSweep(start, delta, sweep, radius) {
  const ranges = [segmentRangeInDisk(start, delta, sweep.start, radius)];
  if (sweep.span > pointEpsilon) {
    ranges.push(segmentRangeInDisk(start, delta, sweep.end, radius));
    const relative = subtract(start, sweep.start);
    const origin = { x: dot(relative, sweep.axis), y: dot(relative, sweep.normal) };
    const travel = { x: dot(delta, sweep.axis), y: dot(delta, sweep.normal) };
    ranges.push(segmentRangeInRect(origin, travel, {
      left: 0, right: sweep.span, top: -radius, bottom: radius,
    }));
  }
  const hits = ranges.filter(Boolean);
  if (!hits.length) return null;
  const from = Math.min(...hits.map(range => range[0]));
  const to = Math.max(...hits.map(range => range[1]));
  return to - from > pointEpsilon ? [from, to] : null;
}

function makeSweep(start, end) {
  const travel = subtract(end, start);
  const span = length(travel);
  const axis = span ? scale(travel, 1 / span) : { x: 0, y: 0 };
  return { start, end, span, axis, normal: { x: -axis.y, y: axis.x } };
}

export function createEditor(canvas, { onChange = () => {} } = {}) {
  const ctx = canvas.getContext('2d');
  const stage = canvas.parentElement;
  const stored = loadNote();
  let note = stored?.note ?? blankNote();
  let camera = stored?.camera ?? { x: 0, y: 24, z: 1 };
  let placeInitialCamera = !stored?.camera;
  let tool = 'pen';
  let brush = { color: '#26364c', width: 3, dashed: false };
  let eraserSize = eraserSizes.initial;
  let selection = new Set();
  let undoStack = [];
  let redoStack = [];
  let gesture = null;
  let pointerGroup = new Map();
  let pinch = null;
  let laser = null;
  let width = 1;
  let height = 1;
  let pixelRatio = 1;
  let frame = 0;
  let saveTimer = 0;
  let pendingSave = false;
  let saved = true;
  let saveError = false;
  const geometry = new WeakMap();

  function getState() {
    return {
      title: note.title, paper: note.paper, zoom: camera.z,
      canUndo: Boolean(undoStack.length), canRedo: Boolean(redoStack.length),
      selectedCount: selection.size, saved, saveError,
    };
  }

  function notify() {
    onChange(getState());
  }

  function persist() {
    clearTimeout(saveTimer);
    if (!pendingSave) return;
    pendingSave = false;
    try {
      // An older offline client can still display a fountain mark as regular
      // ink. Its points retain the widths when opened again in this version.
      const marks = note.marks.map((mark) => mark.type === 'fountain'
        ? { ...mark, type: 'pen', nib: 'fountain' }
        : mark);
      localStorage.setItem(storageKey, JSON.stringify({ doc: { ...note, marks }, cam: camera }));
      saved = true;
      saveError = false;
    } catch {
      saved = false;
      saveError = true;
    }
    notify();
  }

  function changed({ save = false } = {}) {
    if (save) {
      clearTimeout(saveTimer);
      saved = false;
      saveError = false;
      pendingSave = true;
      saveTimer = setTimeout(persist, 120);
    }
    notify();
    requestDraw();
  }

  function pushHistory() {
    undoStack.push(note);
    if (undoStack.length > 45) undoStack.shift();
    redoStack = [];
  }

  function commit(next) {
    if (next === note) return;
    pushHistory();
    note = next;
    extendPaper();
    changed({ save: true });
  }

  function restore(history, opposite) {
    if (!history.length) return;
    cancelInteraction();
    opposite.push(note);
    note = history.pop();
    selection = new Set();
    extendPaper();
    changed({ save: true });
  }

  function extendPaper(bottom = 0) {
    const needed = Math.max(bottom, (height - camera.y) / camera.z + 280);
    if (needed > note.height) {
      note = { ...note, height: Math.ceil(needed / 1000) * 1000 };
    }
  }

  function resize() {
    const box = canvas.getBoundingClientRect();
    if (box.width < 1 || box.height < 1) return;
    width = box.width;
    height = box.height;
    pixelRatio = Math.min(2, window.devicePixelRatio || 1);
    canvas.width = Math.round(width * pixelRatio);
    canvas.height = Math.round(height * pixelRatio);
    if (placeInitialCamera) {
      camera = fittedCamera();
      placeInitialCamera = false;
    }
    extendPaper();
    requestDraw();
    queueMicrotask(notify);
  }

  function requestDraw() {
    if (!frame) frame = requestAnimationFrame(now => {
      frame = 0;
      draw(ctx, now);
      if (laser?.stopped) requestDraw();
    });
  }

  function local(event) {
    const box = canvas.getBoundingClientRect();
    return { x: event.clientX - box.left, y: event.clientY - box.top };
  }

  function model(point) {
    return { x: (point.x - camera.x) / camera.z, y: (point.y - camera.y) / camera.z };
  }

  function paperPoint(point) {
    return { x: clamp(point.x, 0, paperWidth), y: Math.max(0, point.y) };
  }

  function setCamera(next) {
    camera = {
      x: clamp(next.x, -paperWidth * next.z + 36, Math.max(36, width - 36)),
      y: Math.min(44, next.y),
      z: next.z,
    };
    extendPaper();
    changed({ save: true });
  }

  function fittedCamera() {
    const margin = width < 600 ? 16 : 56;
    const zoom = clamp((width - margin) / paperWidth, 0.22, 1);
    return { x: (width - paperWidth * zoom) / 2, y: 24, z: zoom };
  }

  function zoomAt(factor, point) {
    const world = model(point);
    const zoom = clamp(camera.z * factor, 0.22, 4);
    setCamera({ x: point.x - world.x * zoom, y: point.y - world.y * zoom, z: zoom });
  }

  function markGeometry(mark) {
    let result = geometry.get(mark);
    if (result) return result;
    const points = shapeKinds.has(mark.type) ? pointsForShape(mark) : mark.pts;
    const bounds = rectangle(points[0], points[0]);
    const fountain = mark.type === 'fountain';
    const path = fountain ? fountainPath(points, mark) : new Path2D();
    if (!fountain) path.moveTo(points[0].x, points[0].y);
    for (const point of points.slice(1)) {
      bounds.left = Math.min(bounds.left, point.x);
      bounds.right = Math.max(bounds.right, point.x);
      bounds.top = Math.min(bounds.top, point.y);
      bounds.bottom = Math.max(bounds.bottom, point.y);
      if (!fountain) path.lineTo(point.x, point.y);
    }
    if (!fountain && points.length === 1) path.lineTo(points[0].x + 0.01, points[0].y);
    result = { points, bounds: inflate(bounds, ruleWidth(mark) / 2), path };
    geometry.set(mark, result);
    return result;
  }

  function paintPaper(context, view) {
    context.fillStyle = '#fdfdff';
    context.fillRect(0, 0, paperWidth, note.height);
    const step = 28;
    const start = Math.max(0, Math.floor(view.top / step) * step);
    const end = Math.min(note.height, view.bottom + step);
    context.fillStyle = '#d7e1ec';
    context.strokeStyle = '#e1e8f0';
    context.lineWidth = 0.85;
    context.beginPath();
    if (note.paper === 'grid') {
      for (let x = 0; x <= paperWidth; x += step) {
        context.moveTo(x, start);
        context.lineTo(x, end);
      }
    }
    if (note.paper === 'lines' || note.paper === 'grid') {
      for (let y = start; y <= end; y += step) {
        context.moveTo(0, y);
        context.lineTo(paperWidth, y);
      }
      context.stroke();
    }
    if (note.paper === 'lines') {
      context.strokeStyle = '#edd5de';
      context.beginPath();
      context.moveTo(88, start);
      context.lineTo(88, end);
      context.stroke();
    }
    if (note.paper === 'dots') {
      for (let y = start; y <= end; y += step) {
        for (let x = 0; x <= paperWidth; x += step) {
          context.moveTo(x + 1.15, y);
          context.arc(x, y, 1.15, 0, 2 * Math.PI);
        }
      }
      context.fill();
    }
  }

  function paintMark(context, mark, { live = false, opacity = 1 } = {}) {
    const points = mark.pts;
    context.save();
    if (mark.type === 'fountain') {
      context.fillStyle = mark.color;
      context.fill(live ? fountainPath(fountainPoints(points), mark) : markGeometry(mark).path);
      context.restore();
      return;
    }
    context.strokeStyle = mark.color;
    context.lineWidth = ruleWidth(mark);
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.globalAlpha = opacity * brushAlpha(mark.type);
    if (mark.dashed) {
      context.setLineDash(dashPattern(mark));
      context.lineDashOffset = mark.phase || 0;
    }
    if (live && !shapeKinds.has(mark.type)) {
      context.beginPath();
      context.moveTo(points[0].x, points[0].y);
      if (points.length === 1) context.lineTo(points[0].x + 0.01, points[0].y);
      else {
        traceSmooth(points,
          (_, control, end) => context.quadraticCurveTo(control.x, control.y, end.x, end.y),
          (_, end) => context.lineTo(end.x, end.y),
        );
      }
      context.stroke();
    } else if (live) {
      const outline = pointsForShape(mark);
      context.beginPath();
      context.moveTo(outline[0].x, outline[0].y);
      for (const point of outline.slice(1)) context.lineTo(point.x, point.y);
      context.stroke();
    } else {
      context.stroke(markGeometry(mark).path);
    }
    context.restore();
  }

  function selectionBounds() {
    let bounds = null;
    for (const mark of selection) {
      const other = markGeometry(mark).bounds;
      if (bounds === null) bounds = { ...other };
      else {
        bounds.left = Math.min(bounds.left, other.left);
        bounds.right = Math.max(bounds.right, other.right);
        bounds.top = Math.min(bounds.top, other.top);
        bounds.bottom = Math.max(bounds.bottom, other.bottom);
      }
    }
    return bounds;
  }

  function selectionOutline(context, bounds, offset, marquee) {
    const x = bounds.left + offset.x;
    const y = bounds.top + offset.y;
    const w = bounds.right - bounds.left;
    const h = bounds.bottom - bounds.top;
    context.save();
    context.strokeStyle = '#305fc0';
    context.fillStyle = '#326cdd18';
    context.lineWidth = 1.1 / camera.z;
    context.setLineDash([5 / camera.z, 3 / camera.z]);
    if (marquee) context.fillRect(x, y, w, h);
    context.strokeRect(x, y, w, h);
    context.restore();
  }

  function draw(context, now, overlays = true) {
    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    context.fillStyle = '#e6edf1';
    context.fillRect(0, 0, width, height);
    context.save();
    context.translate(camera.x, camera.y);
    context.scale(camera.z, camera.z);
    const view = rectangle(model({ x: 0, y: 0 }), model({ x: width, y: height }));
    context.strokeStyle = '#d6dee8';
    context.lineWidth = 1 / camera.z;
    context.strokeRect(0, 0, paperWidth, note.height);
    context.beginPath();
    context.rect(0, 0, paperWidth, note.height);
    context.clip();
    paintPaper(context, view);

    const moveOffset = overlays && gesture?.kind === 'move' ? gesture.delta : { x: 0, y: 0 };
    const marks = overlays && gesture?.kind === 'erase' ? gesture.marks : note.marks;
    for (const mark of marks) {
      const bounds = markGeometry(mark).bounds;
      if (overlays && gesture?.kind === 'move' && selection.has(mark)) {
        context.save();
        context.translate(moveOffset.x, moveOffset.y);
        paintMark(context, mark);
        context.restore();
      } else if (overlaps(bounds, view)) paintMark(context, mark);
    }
    if (overlays && gesture?.kind === 'draw') paintMark(context, gesture.mark, { live: true });
    if (overlays && laser) {
      const opacity = laser.stopped ? Math.max(0, 1 - (now - laser.stopped) / 1500) : 1;
      if (opacity > 0) paintMark(context, laser.mark, { live: true, opacity });
      else laser = null;
    }
    if (overlays) {
      const bounds = selectionBounds();
      if (bounds) selectionOutline(context, inflate(bounds, 5 / camera.z), moveOffset, false);
      if (gesture?.kind === 'marquee') {
        selectionOutline(context, rectangle(gesture.start, gesture.end), { x: 0, y: 0 }, true);
      }
    }
    context.restore();
  }

  function eraseAcross(marks, start, end) {
    const sweep = makeSweep(start, end);
    const eraserRadius = eraserSize / (2 * camera.z);
    const region = inflate(rectangle(start, end), eraserRadius);
    let erased = false;
    const result = marks.flatMap(mark => {
      const { bounds, points } = markGeometry(mark);
      if (!overlaps(bounds, region)) return [mark];
      const inkRadius = ruleWidth(mark) / 2;
      if (points.length === 1) {
        if (distanceToSegment(points[0], start, end) >
            eraserRadius + inkRadius * (points[0].weight ?? 1)) return [mark];
        erased = true;
        return [];
      }
      const fragments = [];
      let ink = [];
      let phase = mark.phase || 0;
      let travelled = phase;
      let changedMark = false;
      function keep(a, b, from, to, segmentLength) {
        if (to - from <= pointEpsilon) return;
        if (!ink.length) {
          phase = travelled + from * segmentLength;
          ink.push(inkLerp(a, b, from));
        }
        ink.push(inkLerp(a, b, to));
      }
      function finish() {
        if (ink.length) fragments.push({ ...mark, pts: ink, smooth: true, phase });
        ink = [];
      }
      for (let index = 1; index < points.length; index++) {
        const a = points[index - 1];
        const b = points[index];
        const delta = subtract(b, a);
        const segmentLength = length(delta);
        const radius = inkRadius * Math.max(a.weight ?? 1, b.weight ?? 1);
        const cut = overlaps(inflate(rectangle(a, b), radius), region)
          ? segmentRangeInSweep(a, delta, sweep, eraserRadius + radius)
          : null;
        if (cut) {
          erased = true;
          changedMark = true;
          if (shapeKinds.has(mark.type)) return [];
          keep(a, b, 0, cut[0], segmentLength);
          finish();
          keep(a, b, cut[1], 1, segmentLength);
        } else keep(a, b, 0, 1, segmentLength);
        travelled += segmentLength;
      }
      if (!changedMark) return [mark];
      finish();
      return fragments;
    });
    return erased ? result : marks;
  }

  function hitsRectangle(mark, box) {
    const { bounds, points } = markGeometry(mark);
    if (!overlaps(bounds, box)) return false;
    const target = inflate(box, ruleWidth(mark) / 2);
    if (points.some(point => contains(target, point))) return true;
    return points.slice(1).some((point, index) =>
      segmentRangeInRect(points[index], subtract(point, points[index]), target));
  }

  function pointerSamples(event) {
    const list = event.getCoalescedEvents?.() ?? [];
    if (!list.length) return [event];
    const last = list.at(-1);
    return last.clientX === event.clientX && last.clientY === event.clientY ? list : [...list, event];
  }

  function updatePointer(event) {
    const point = local(event);
    pointerGroup.set(event.pointerId, { point, type: event.pointerType });
    if (pinch) {
      if (pointerGroup.size < 2) return;
      const [first, second] = [...pointerGroup.values()].map(pointer => pointer.point);
      const center = lerp(first, second, 0.5);
      const zoom = clamp(pinch.camera.z * length(subtract(first, second)) / pinch.span, 0.22, 4);
      setCamera({ x: center.x - pinch.anchor.x * zoom, y: center.y - pinch.anchor.y * zoom, z: zoom });
      return;
    }
    if (!gesture || gesture.pointer !== event.pointerId) return;
    if (gesture.kind === 'pan') {
      const delta = subtract(point, gesture.start);
      setCamera({ ...gesture.camera, x: gesture.camera.x + delta.x, y: gesture.camera.y + delta.y });
      return;
    }
    if (gesture.kind === 'marquee') {
      gesture.end = paperPoint(model(point));
      requestDraw();
      return;
    }
    if (gesture.kind === 'move') {
      const delta = subtract(model(point), gesture.start);
      const bounds = gesture.bounds;
      gesture.delta = {
        x: clamp(delta.x, Math.min(0, -bounds.left), Math.max(0, paperWidth - bounds.right)),
        y: Math.max(Math.min(0, -bounds.top), delta.y),
      };
      requestDraw();
      return;
    }
    for (const sample of pointerSamples(event)) {
      const world = paperPoint(model(local(sample)));
      if (gesture.kind === 'erase') {
        if (length(subtract(world, gesture.last)) > pointEpsilon) {
          gesture.marks = eraseAcross(gesture.marks, gesture.last, world);
          gesture.last = world;
        }
      } else {
        const mark = gesture.kind === 'laser' ? laser.mark : gesture.mark;
        if (shapeKinds.has(mark.type)) {
          mark.pts[1] = world;
        } else if (length(subtract(world, mark.pts.at(-1))) >= 0.35 / camera.z) {
          if (mark.type === 'fountain') {
            world.pressure = fountainPressure(sample, mark.pts.at(-1).pressure);
          }
          mark.pts.push(world);
        }
      }
    }
    requestDraw();
  }

  function startPinch() {
    gesture = null;
    laser = null;
    const [first, second] = [...pointerGroup.values()].map(pointer => pointer.point);
    pinch = {
      camera: { ...camera },
      anchor: model(lerp(first, second, 0.5)),
      span: Math.max(1, length(subtract(first, second))),
    };
    requestDraw();
  }

  function pointerDown(event) {
    const invertedPen = event.pointerType === 'pen' &&
      (event.button === 5 || (event.buttons & 32) !== 0);
    if (event.button !== 0 && event.button !== 1 && !invertedPen) return;
    if (pointerGroup.size && !(event.pointerType === 'touch' &&
      [...pointerGroup.values()].every(pointer => pointer.type === 'touch'))) return;
    event.preventDefault();
    const point = local(event);
    try {
      canvas.setPointerCapture(event.pointerId);
    } catch {
      // Synthetic pointer events may not have an active browser pointer.
    }
    pointerGroup.set(event.pointerId, { point, type: event.pointerType });
    if (pointerGroup.size >= 2) {
      if (pointerGroup.size === 2) startPinch();
      return;
    }
    const base = { pointer: event.pointerId };
    if (tool === 'pan' || event.button === 1 || spaceHeld) {
      gesture = { ...base, kind: 'pan', start: point, camera: { ...camera } };
      return;
    }
    const start = model(point);
    if (start.x < 0 || start.x > paperWidth || start.y < 0) return;
    if (tool === 'select' || event.shiftKey) {
      const bounds = selectionBounds();
      if (bounds && contains(inflate(bounds, 5 / camera.z), start)) {
        gesture = { ...base, kind: 'move', start, bounds, delta: { x: 0, y: 0 } };
      } else {
        gesture = { ...base, kind: 'marquee', start, end: start };
      }
    } else if (tool === 'eraser' || invertedPen) {
      selection = new Set();
      gesture = { ...base, kind: 'erase', last: start, marks: eraseAcross(note.marks, start, start) };
    } else {
      selection = new Set();
      const mark = {
        type: tool, color: tool === 'laser' ? '#ee3858' : brush.color, w: brush.width,
        dashed: tool !== 'laser' && brush.dashed, phase: 0, pts: [start],
      };
      if (tool === 'fountain') start.pressure = fountainPressure(event);
      if (tool === 'laser') {
        laser = { mark, stopped: 0 };
        gesture = { ...base, kind: 'laser' };
      } else {
        if (shapeKinds.has(tool)) mark.pts.push(start);
        gesture = { ...base, kind: 'draw', mark };
      }
    }
    changed();
  }

  function pointerEnd(event, canceled) {
    if (!pointerGroup.has(event.pointerId)) return;
    if (!canceled && !pinch) updatePointer(event);
    pointerGroup.delete(event.pointerId);
    if (pinch) {
      if (pointerGroup.size >= 2) startPinch();
      else if (!pointerGroup.size) pinch = null;
      changed();
      return;
    }
    if (!gesture || gesture.pointer !== event.pointerId) return;
    const finished = gesture;
    gesture = null;
    if (finished.kind === 'laser' && laser) laser.stopped = performance.now();
    if (canceled) {
      changed();
      return;
    }
    if (finished.kind === 'draw') {
      const mark = finished.mark;
      const shape = shapeKinds.has(mark.type);
      if (!shape || length(subtract(mark.pts[0], mark.pts.at(-1))) > 1 / camera.z) {
        const pts = shape ? mark.pts
          : mark.type === 'fountain' ? fountainPoints(mark.pts) : smoothPoints(mark.pts);
        const complete = { ...mark, pts, smooth: true };
        commit({ ...note, marks: [...note.marks, complete],
          height: Math.max(note.height, markGeometry(complete).bounds.bottom + 280) });
        return;
      }
    }
    if (finished.kind === 'erase' && finished.marks !== note.marks) {
      commit({ ...note, marks: finished.marks });
      return;
    }
    if (finished.kind === 'marquee') {
      const box = rectangle(finished.start, finished.end);
      if (length(subtract(finished.start, finished.end)) < 3 / camera.z) {
        const point = inflate(box, 5 / camera.z);
        const mark = note.marks.findLast(mark => hitsRectangle(mark, point));
        selection = new Set(mark ? [mark] : []);
      } else {
        selection = new Set(note.marks.filter(mark => hitsRectangle(mark, box)));
      }
    }
    if (finished.kind === 'move' && length(finished.delta) > 0.5 / camera.z) {
      const moved = new Set();
      const marks = note.marks.map(mark => {
        if (!selection.has(mark)) return mark;
        const result = {
          ...mark,
          pts: mark.pts.map(point => ({ ...point, ...add(point, finished.delta) })),
        };
        moved.add(result);
        return result;
      });
      selection = moved;
      commit({ ...note, marks, height: Math.max(note.height, selectionBounds().bottom + 280) });
      return;
    }
    changed();
  }

  function cancelInteraction() {
    if (gesture?.kind === 'laser' && laser) laser.stopped = performance.now();
    gesture = null;
    pointerGroup.clear();
    pinch = null;
  }

  function clearSelection() {
    cancelInteraction();
    selection = new Set();
    changed();
  }

  function deleteSelection() {
    if (!selection.size) return false;
    cancelInteraction();
    const marks = note.marks.filter(mark => !selection.has(mark));
    selection = new Set();
    commit({ ...note, marks });
    return true;
  }

  async function exportPng() {
    const image = document.createElement('canvas');
    image.width = canvas.width;
    image.height = canvas.height;
    draw(image.getContext('2d'), performance.now(), false);
    const blob = await new Promise(resolve => image.toBlob(resolve, 'image/png'));
    if (!blob) throw new Error('Không thể tạo ảnh PNG.');
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    const filename = note.title.replace(/[<>:"/\\|?*\u0000-\u001f]/g, ' ').trim() || 'VietInk';
    link.download = filename + '.png';
    link.href = url;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    return blob;
  }

  let spaceHeld = false;
  function spaceDown(event) {
    if (event.code !== 'Space' || event.defaultPrevented) return;
    if (event.target instanceof Element && event.target.closest('input, textarea, select, button, [contenteditable=true]')) return;
    if (event.target instanceof Element &&
      (event.target === document.body || stage.contains(event.target))) {
      event.preventDefault();
      spaceHeld = true;
    }
  }

  canvas.addEventListener('pointerdown', pointerDown);
  canvas.addEventListener('pointermove', event => {
    if (pointerGroup.has(event.pointerId)) updatePointer(event);
  });
  canvas.addEventListener('pointerup', event => pointerEnd(event, false));
  canvas.addEventListener('pointercancel', event => pointerEnd(event, true));
  canvas.addEventListener('lostpointercapture', event => pointerEnd(event, true));
  canvas.addEventListener('wheel', event => {
    event.preventDefault();
    if (gesture && gesture.kind !== 'pan') return;
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? height : 1;
    if (event.ctrlKey || event.metaKey) {
      zoomAt(Math.exp(-event.deltaY * unit * 0.002), local(event));
    } else {
      setCamera({ ...camera, x: camera.x - event.deltaX * unit, y: camera.y - event.deltaY * unit });
    }
  }, { passive: false });
  window.addEventListener('keydown', spaceDown);
  window.addEventListener('keyup', event => {
    if (event.code === 'Space') spaceHeld = false;
  });
  window.addEventListener('blur', () => {
    spaceHeld = false;
    cancelInteraction();
    requestDraw();
  });
  window.addEventListener('pagehide', persist);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') persist();
  });
  new ResizeObserver(resize).observe(stage);
  resize();

  return {
    getState,
    setTool(next) {
      if (!tools.has(next) || next === tool) return;
      cancelInteraction();
      tool = next;
      if (next !== 'select') selection = new Set();
      changed();
    },
    setBrush({ color, width: size, dashed }) {
      if (typeof color === 'string') brush.color = color;
      if (Number.isFinite(size)) brush.width = clamp(size, 0.2, 60);
      if (typeof dashed === 'boolean') brush.dashed = dashed;
    },
    setEraserSize(size) {
      if (Number.isFinite(size)) eraserSize = clamp(size, eraserSizes.min, eraserSizes.max);
    },
    setPaper(paper) {
      if (!paperKinds.has(paper) || note.paper === paper) return;
      commit({ ...note, paper });
    },
    setTitle(title) {
      if (typeof title !== 'string' || title === note.title) return;
      note = { ...note, title };
      changed({ save: true });
    },
    undo: () => restore(undoStack, redoStack),
    redo: () => restore(redoStack, undoStack),
    clearSelection,
    deleteSelection,
    newNote() {
      clearSelection();
      camera = fittedCamera();
      commit(blankNote());
    },
    zoomBy(factor) {
      if (factor > 0 && Number.isFinite(factor)) zoomAt(factor, { x: width / 2, y: height / 2 });
    },
    fit: () => setCamera(fittedCamera()),
    exportPng,
  };
}
