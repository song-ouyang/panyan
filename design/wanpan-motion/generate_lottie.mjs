import fs from 'node:fs';
import path from 'node:path';

const PLAYER_PROJECT = process.argv[2];
const APP_ASSETS = process.argv[3];

if (!PLAYER_PROJECT || !APP_ASSETS) {
  console.error(
    'Usage: node generate_lottie.mjs <player-project-dir> <flutter-assets-dir>',
  );
  process.exit(2);
}

const rgba = (hex) => {
  const value = hex.replace('#', '');
  return [
    Number.parseInt(value.slice(0, 2), 16) / 255,
    Number.parseInt(value.slice(2, 4), 16) / 255,
    Number.parseInt(value.slice(4, 6), 16) / 255,
    1,
  ];
};

const colors = {
  cat: rgba('#171A1E'),
  ink: rgba('#24343C'),
  muted: rgba('#69777E'),
  coral: rgba('#FF6B52'),
  coralShadow: rgba('#D94F3A'),
  sunflower: rgba('#FFC943'),
  grape: rgba('#9A78E8'),
  mint: rgba('#9DD5B0'),
  sky: rgba('#70C9E8'),
  cream: rgba('#FFFDF7'),
  border: rgba('#E9DCC7'),
  white: rgba('#FFFFFF'),
};

const slots = Object.fromEntries(
  Object.entries(colors).map(([name, value]) => [
    `${name}Color`,
    { p: { a: 0, k: value } },
  ]),
);

const controls = {
  controls: [
    { sid: 'coralColor', label: '品牌珊瑚色' },
    { sid: 'catColor', label: '黑猫颜色' },
    { sid: 'sunflowerColor', label: '庆祝星光' },
    { sid: 'grapeColor', label: '葡萄岩点' },
    { sid: 'mintColor', label: '成功状态' },
  ],
};

const curves = {
  entrance: [.2, .75, .34, .94],
  settle: [0, .65, .51, .99],
  travel: [1, .49, 0, .55],
  exit: [1, .02, .54, .42],
  linear: [0, 0, 1, 1],
};

const prop = (k) => ({ a: 0, k });
const asArray = (value) => (Array.isArray(value) ? value : [value]);

function animated(entries) {
  return {
    a: 1,
    k: entries.map((entry, index) => {
      const previous = entries[index - 1];
      const next = entries[index + 1];
      const frame = { t: entry.t, s: asArray(entry.v) };
      if (next) {
        frame.e = asArray(next.v);
        const curve = entry.curve ?? curves.settle;
        frame.o = { x: [curve[0]], y: [curve[1]] };
      }
      if (previous) {
        const curve = previous.curve ?? curves.settle;
        frame.i = { x: [curve[2]], y: [curve[3]] };
      }
      if (entry.hold) frame.h = 1;
      return frame;
    }),
  };
}

const colorProp = (name) => ({
  a: 0,
  k: colors[name],
  sid: `${name}Color`,
});

const transform = ({
  position = [256, 256, 0],
  anchor = [0, 0, 0],
  scale = [100, 100, 100],
  rotation = 0,
  opacity = 100,
} = {}) => ({
  o: Array.isArray(opacity) && opacity[0]?.t != null ? animated(opacity) : prop(opacity),
  r:
    Array.isArray(rotation) && rotation[0]?.t != null
      ? animated(rotation)
      : prop(rotation),
  p:
    Array.isArray(position) && position[0]?.t != null
      ? animated(position)
      : prop(position),
  a: prop(anchor),
  s:
    Array.isArray(scale) && scale[0]?.t != null ? animated(scale) : prop(scale),
});

const groupTransform = ({ position = [0, 0], scale = [100, 100] } = {}) => ({
  ty: 'tr',
  p: prop(position),
  a: prop([0, 0]),
  s: prop(scale),
  r: prop(0),
  o: prop(100),
  sk: prop(0),
  sa: prop(0),
});

const fill = (name, opacity = 100) => ({
  ty: 'fl',
  c: colorProp(name),
  o: prop(opacity),
  r: 1,
});

const stroke = (name, width, opacity = 100) => ({
  ty: 'st',
  c: colorProp(name),
  o: prop(opacity),
  w: prop(width),
  lc: 2,
  lj: 2,
  ml: 4,
});

const ellipse = (name, position, size, color, strokeColor, strokeWidth = 0) => ({
  ty: 'gr',
  nm: name,
  it: [
    { ty: 'el', nm: `${name} shape`, p: prop(position), s: prop(size), d: 1 },
    fill(color),
    ...(strokeColor ? [stroke(strokeColor, strokeWidth)] : []),
    groupTransform(),
  ],
});

const roundedRect = (
  name,
  position,
  size,
  radius,
  color,
  strokeColor,
  strokeWidth = 0,
) => ({
  ty: 'gr',
  nm: name,
  it: [
    {
      ty: 'rc',
      nm: `${name} shape`,
      p: prop(position),
      s: prop(size),
      r: prop(radius),
      d: 1,
    },
    fill(color),
    ...(strokeColor ? [stroke(strokeColor, strokeWidth)] : []),
    groupTransform(),
  ],
});

const pathShape = (vertices, closed = false) => ({
  ty: 'sh',
  ks: prop({
    i: vertices.map(() => [0, 0]),
    o: vertices.map(() => [0, 0]),
    v: vertices,
    c: closed,
  }),
});

const pathGroup = (
  name,
  vertices,
  color,
  width,
  { closed = false, fillColor = null, trim = null } = {},
) => ({
  ty: 'gr',
  nm: name,
  it: [
    pathShape(vertices, closed),
    ...(fillColor ? [fill(fillColor)] : []),
    ...(width > 0 ? [stroke(color, width)] : []),
    ...(trim
      ? [
          {
            ty: 'tm',
            s: prop(0),
            e: animated(trim),
            o: prop(0),
            m: 1,
          },
        ]
      : []),
    groupTransform(),
  ],
});

const star = (name, position, outerRadius, color) => ({
  ty: 'gr',
  nm: name,
  it: [
    {
      ty: 'sr',
      sy: 1,
      d: 1,
      pt: prop(5),
      p: prop(position),
      r: prop(0),
      or: prop(outerRadius),
      os: prop(0),
      ir: prop(outerRadius * .46),
      is: prop(0),
    },
    fill(color),
    groupTransform(),
  ],
});

function shapeLayer(name, index, op, shapes, options = {}) {
  return {
    ddd: 0,
    ind: index,
    ty: 4,
    nm: name,
    sr: 1,
    ks: transform(options),
    ao: 0,
    shapes,
    ip: options.ip ?? 0,
    op,
    st: 0,
    bm: 0,
  };
}

function catHeadShapes() {
  return [
    ellipse('head', [0, -42], [184, 150], 'cat'),
    pathGroup(
      'left ear',
      [[-82, -74], [-62, -142], [-18, -87]],
      'cat',
      0,
      { closed: true, fillColor: 'cat' },
    ),
    pathGroup(
      'right ear',
      [[18, -87], [62, -142], [82, -74]],
      'cat',
      0,
      { closed: true, fillColor: 'cat' },
    ),
  ];
}

function catBodyShapes({ tail = true } = {}) {
  return [
    ellipse('body', [0, 48], [164, 158], 'cat'),
    ...(tail
      ? [pathGroup('tail', [[66, 58], [124, 57], [136, 7]], 'cat', 30)]
      : []),
  ];
}

function catBaseShapes() {
  return [...catHeadShapes(), ...catBodyShapes()];
}

function catPupilShapes() {
  return [
    ellipse('left pupil', [-33, -43], [18, 27], 'cat'),
    ellipse('right pupil', [43, -43], [18, 27], 'cat'),
  ];
}

function catFaceShapes({ paws = true, pupils = true } = {}) {
  return [
    ...(paws
      ? [
          ellipse('left paw', [-72, 43], [58, 48], 'cat'),
          ellipse('right paw', [72, 43], [58, 48], 'cat'),
        ]
      : []),
    ...(pupils ? catPupilShapes() : []),
    ellipse('left eye', [-38, -48], [48, 61], 'white'),
    ellipse('right eye', [38, -48], [48, 61], 'white'),
    pathGroup(
      'mouth',
      [[-10, -5], [0, 7], [10, -5]],
      'coral',
      0,
      { closed: true, fillColor: 'coral' },
    ),
    pathGroup('left whiskers', [[-72, -18], [-106, -24]], 'white', 5),
    pathGroup('left whiskers low', [[-70, -4], [-104, 2]], 'white', 5),
    pathGroup('right whiskers', [[72, -18], [106, -24]], 'white', 5),
    pathGroup('right whiskers low', [[70, -4], [104, 2]], 'white', 5),
  ];
}

function holdShapes(color = 'coral', size = [112, 78]) {
  return [
    ellipse('bolt', [0, 0], [16, 16], 'ink'),
    ellipse('hold', [0, 0], size, color, 'ink', 7),
    ellipse('hold shadow', [0, 8], [size[0], size[1]], 'coralShadow'),
  ];
}

function scene(name, op, layers) {
  return {
    v: '5.12.2',
    fr: 60,
    ip: 0,
    op,
    w: 512,
    h: 512,
    nm: name,
    ddd: 0,
    assets: [],
    slots,
    layers,
  };
}

function particleLayer({
  name,
  index,
  op,
  start,
  origin,
  target,
  color,
  size,
  starShape = false,
  rotation = 0,
  travelFrames = 14,
  fadeFrame = 17,
  duration = 22,
}) {
  const shapes = starShape
    ? [star(name, [0, 0], size, color)]
    : [roundedRect(name, [0, 0], [size * 1.35, size * .68], size, color)];
  return shapeLayer(name, index, op, shapes, {
    position: [
      { t: start, v: [...origin, 0], curve: curves.entrance },
      { t: start + travelFrames, v: [...target, 0], curve: curves.settle },
      { t: start + duration, v: [...target, 0] },
    ],
    scale: [
      { t: start, v: [35, 35, 100], curve: curves.entrance },
      { t: start + 6, v: [108, 108, 100], curve: curves.settle },
      { t: start + 11, v: [100, 100, 100] },
    ],
    rotation: [
      { t: start, v: [0], curve: curves.travel },
      { t: start + travelFrames, v: [rotation] },
    ],
    opacity: [
      { t: start, v: [0], curve: curves.entrance },
      { t: start + 3, v: [100], curve: curves.exit },
      { t: start + fadeFrame, v: [100], curve: curves.exit },
      { t: start + duration, v: [0] },
    ],
    ip: start,
  });
}

function fireworkLayer({ name, index, op, center, color, start, rotation = 0 }) {
  const angles = [-90, -30, 30, 90, 150, 210];
  const rays = angles.map((angle, rayIndex) => {
    const radians = (angle * Math.PI) / 180;
    const inner = [Math.cos(radians) * 28, Math.sin(radians) * 28];
    const outer = [Math.cos(radians) * 60, Math.sin(radians) * 60];
    return pathGroup(`ray ${rayIndex + 1}`, [inner, outer], color, 7, {
      trim: [
        {
          t: start + (rayIndex % 2) * 3,
          v: [0],
          curve: curves.entrance,
        },
        { t: start + 15 + (rayIndex % 2) * 3, v: [100] },
      ],
    });
  });
  return shapeLayer(name, index, op, [star('firework center', [0, 0], 12, color), ...rays], {
    position: [...center, 0],
    scale: [
      { t: start, v: [88, 88, 100], curve: curves.entrance },
      { t: start + 18, v: [100, 100, 100] },
    ],
    rotation: [
      { t: start, v: [rotation - 3], curve: curves.settle },
      { t: start + 21, v: [rotation] },
    ],
    opacity: [
      { t: start, v: [0], curve: curves.entrance },
      { t: start + 7, v: [82] },
    ],
    ip: start,
  });
}

function buildSendSuccess() {
  const op = 60;
  const catPosition = [
    { t: 0, v: [256, 360, 0], curve: curves.entrance },
    { t: 7, v: [256, 326, 0], curve: curves.settle },
    { t: 15, v: [256, 304, 0], curve: curves.settle },
    { t: 24, v: [256, 310, 0] },
  ];
  const catScale = [
    { t: 0, v: [72, 72, 100], curve: curves.entrance },
    { t: 12, v: [106, 106, 100], curve: curves.settle },
    { t: 22, v: [100, 100, 100] },
  ];
  const layers = [
    particleLayer({
      name: 'celebration star left',
      index: 1,
      op,
      start: 23,
      origin: [150, 238],
      target: [76, 220],
      color: 'sunflower',
      size: 15,
      starShape: true,
      rotation: -24,
      duration: 22,
    }),
    particleLayer({
      name: 'celebration star right',
      index: 2,
      op,
      start: 25,
      origin: [362, 238],
      target: [436, 212],
      color: 'grape',
      size: 13,
      starShape: true,
      rotation: 26,
      duration: 22,
    }),
    particleLayer({
      name: 'celebration coral accent',
      index: 3,
      op,
      start: 27,
      origin: [256, 256],
      target: [256, 170],
      color: 'coral',
      size: 12,
      rotation: 40,
      duration: 20,
    }),
    shapeLayer('left celebration arm and paw', 4, op, [
      pathGroup('left open arm', [[-42, 8], [-118, -54]], 'cat', 28),
      ellipse('left open paw', [-126, -60], [62, 50], 'cat'),
    ], {
      position: catPosition,
      scale: catScale,
      rotation: [
        { t: 7, v: [22], curve: curves.entrance },
        { t: 19, v: [-5], curve: curves.settle },
        { t: 28, v: [0] },
      ],
      opacity: [
        { t: 4, v: [0], curve: curves.entrance },
        { t: 9, v: [100] },
      ],
      ip: 4,
    }),
    shapeLayer('right celebration arm and paw', 5, op, [
      pathGroup('right open arm', [[42, 8], [118, -54]], 'cat', 28),
      ellipse('right open paw', [126, -60], [62, 50], 'cat'),
    ], {
      position: catPosition,
      scale: catScale,
      rotation: [
        { t: 7, v: [-22], curve: curves.entrance },
        { t: 19, v: [5], curve: curves.settle },
        { t: 28, v: [0] },
      ],
      opacity: [
        { t: 4, v: [0], curve: curves.entrance },
        { t: 9, v: [100] },
      ],
      ip: 4,
    }),
    shapeLayer('celebrating cat face', 6, op, catFaceShapes({ paws: false }), {
      position: catPosition,
      scale: catScale,
      opacity: [
        { t: 0, v: [0], curve: curves.entrance },
        { t: 5, v: [100] },
      ],
    }),
    shapeLayer('celebrating cat head', 7, op, catHeadShapes(), {
      position: catPosition,
      scale: catScale,
      opacity: [
        { t: 0, v: [0], curve: curves.entrance },
        { t: 5, v: [100] },
      ],
    }),
    shapeLayer('celebrating cat body', 8, op, catBodyShapes(), {
      position: catPosition,
      scale: catScale,
      opacity: [
        { t: 0, v: [0], curve: curves.entrance },
        { t: 5, v: [100] },
      ],
    }),
    shapeLayer('celebration landing hold', 9, op, holdShapes('coral', [152, 70]), {
      position: [256, 430, 0],
      scale: [
        { t: 0, v: [84, 92, 100], curve: curves.entrance },
        { t: 10, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 0, v: [0], curve: curves.entrance },
        { t: 4, v: [100] },
      ],
    }),
    fireworkLayer({
      name: 'left sunflower firework',
      index: 10,
      op,
      center: [126, 128],
      color: 'sunflower',
      start: 14,
      rotation: -6,
    }),
    fireworkLayer({
      name: 'right grape firework',
      index: 11,
      op,
      center: [386, 124],
      color: 'grape',
      start: 17,
      rotation: 8,
    }),
  ];
  return scene('Wanpan - Open Paws Firework Send Success', op, layers);
}

function buildGradeMilestone() {
  const op = 66;
  const catPosition = [
    { t: 0, v: [256, 246, 0], curve: curves.entrance },
    { t: 10, v: [256, 184, 0], curve: curves.settle },
    { t: 18, v: [256, 190, 0] },
  ];
  const catOpacity = [
    { t: 0, v: [0], curve: curves.entrance },
    { t: 5, v: [100] },
  ];
  const badgeShapes = (name, color) => [
    ellipse(`${name} text safe area`, [0, -3], [74, 58], 'cream', 'ink', 5),
    ellipse(`${name} face`, [0, 0], [104, 88], color, 'ink', 7),
    ellipse(`${name} depth`, [0, 8], [104, 88], 'border'),
  ];

  return scene('Wanpan - Configurable Grade Progression', op, [
    particleLayer({
      name: 'latest grade star',
      index: 1,
      op,
      start: 39,
      origin: [376, 314],
      target: [430, 238],
      color: 'sunflower',
      size: 15,
      starShape: true,
      rotation: 26,
      duration: 18,
      fadeFrame: 13,
    }),
    particleLayer({
      name: 'latest grade accent',
      index: 2,
      op,
      start: 41,
      origin: [376, 314],
      target: [452, 306],
      color: 'grape',
      size: 11,
      rotation: 34,
      duration: 17,
      fadeFrame: 12,
    }),
    shapeLayer('milestone left open paw', 3, op, [
      pathGroup('left forearm', [[-35, 6], [-78, -30]], 'cat', 24),
      ellipse('left paw', [-83, -34], [54, 44], 'cat'),
    ], {
      position: catPosition,
      scale: [68, 68, 100],
      rotation: [
        { t: 34, v: [18], curve: curves.entrance },
        { t: 44, v: [-4], curve: curves.settle },
        { t: 52, v: [0] },
      ],
      opacity: [
        { t: 34, v: [0], curve: curves.entrance },
        { t: 38, v: [100] },
      ],
      ip: 34,
    }),
    shapeLayer('milestone right open paw', 4, op, [
      pathGroup('right forearm', [[35, 6], [78, -30]], 'cat', 24),
      ellipse('right paw', [83, -34], [54, 44], 'cat'),
    ], {
      position: catPosition,
      scale: [68, 68, 100],
      rotation: [
        { t: 34, v: [-18], curve: curves.entrance },
        { t: 44, v: [4], curve: curves.settle },
        { t: 52, v: [0] },
      ],
      opacity: [
        { t: 34, v: [0], curve: curves.entrance },
        { t: 38, v: [100] },
      ],
      ip: 34,
    }),
    shapeLayer('latest grade badge', 5, op, badgeShapes('latest grade', 'coral'), {
      position: [376, 314, 0],
      scale: [
        { t: 30, v: [70, 70, 100], curve: curves.entrance },
        { t: 38, v: [108, 108, 100], curve: curves.settle },
        { t: 47, v: [100, 100, 100] },
      ],
      rotation: [
        { t: 30, v: [-7], curve: curves.entrance },
        { t: 39, v: [2], curve: curves.settle },
        { t: 47, v: [0] },
      ],
      opacity: [
        { t: 30, v: [0], curve: curves.entrance },
        { t: 34, v: [100] },
      ],
      ip: 30,
    }),
    shapeLayer('middle grade badge', 6, op, badgeShapes('middle grade', 'sunflower'), {
      position: [256, 286, 0],
      scale: [
        { t: 17, v: [82, 82, 100], curve: curves.entrance },
        { t: 27, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 17, v: [0], curve: curves.entrance },
        { t: 21, v: [100] },
      ],
      ip: 17,
    }),
    shapeLayer('starting grade badge', 7, op, badgeShapes('starting grade', 'grape'), {
      position: [136, 314, 0],
      scale: [
        { t: 4, v: [76, 76, 100], curve: curves.entrance },
        { t: 14, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 4, v: [0], curve: curves.entrance },
        { t: 8, v: [100] },
      ],
      ip: 4,
    }),
    shapeLayer('milestone cat face', 8, op, catFaceShapes({ paws: false }), {
      position: catPosition,
      scale: [68, 68, 100],
      opacity: catOpacity,
    }),
    shapeLayer('milestone cat head', 9, op, catHeadShapes(), {
      position: catPosition,
      scale: [68, 68, 100],
      opacity: catOpacity,
    }),
    shapeLayer('milestone cat body', 10, op, catBodyShapes({ tail: false }), {
      position: catPosition,
      scale: [68, 68, 100],
      opacity: catOpacity,
    }),
    shapeLayer('first grade arrow', 11, op, [
      pathGroup(
        'first arrow head',
        [[196, 290], [207, 298], [198, 307]],
        'coral',
        0,
        { closed: true, fillColor: 'coral' },
      ),
      pathGroup('first connector', [[187, 302], [199, 299]], 'coral', 7, {
        trim: [
          { t: 10, v: [0], curve: curves.entrance },
          { t: 19, v: [100] },
        ],
      }),
    ], {
      position: [0, 0, 0],
      opacity: [
        { t: 10, v: [0], curve: curves.entrance },
        { t: 17, v: [100] },
      ],
      ip: 10,
    }),
    shapeLayer('second grade arrow', 12, op, [
      pathGroup(
        'second arrow head',
        [[316, 293], [327, 302], [316, 310]],
        'coral',
        0,
        { closed: true, fillColor: 'coral' },
      ),
      pathGroup('second connector', [[307, 298], [319, 301]], 'coral', 7, {
        trim: [
          { t: 23, v: [0], curve: curves.entrance },
          { t: 32, v: [100] },
        ],
      }),
    ], {
      position: [0, 0, 0],
      opacity: [
        { t: 23, v: [0], curve: curves.entrance },
        { t: 30, v: [100] },
      ],
      ip: 23,
    }),
  ]);
}

function buildRoutePublished() {
  const op = 60;
  const mapPosition = [
    { t: 0, v: [246, 372, 0], curve: curves.entrance },
    { t: 8, v: [246, 342, 0] },
  ];
  const mapScale = [
    { t: 0, v: [90, 90, 100], curve: curves.entrance },
    { t: 8, v: [100, 100, 100] },
  ];
  const catPosition = [
    { t: 0, v: [330, 234, 0], curve: curves.entrance },
    { t: 10, v: [330, 190, 0], curve: curves.settle },
    { t: 18, v: [330, 196, 0] },
  ];
  const catOpacity = [
    { t: 0, v: [0], curve: curves.entrance },
    { t: 5, v: [100] },
  ];
  const penPosition = [
    { t: 8, v: [150, 380, 0], curve: curves.travel },
    { t: 16, v: [202, 350, 0], curve: curves.travel },
    { t: 24, v: [252, 372, 0], curve: curves.travel },
    { t: 29, v: [282, 342, 0], curve: curves.travel },
    { t: 34, v: [330, 306, 0], curve: curves.settle },
    { t: 43, v: [300, 264, 0] },
  ];

  return scene('Wanpan - Cat Finishes Record And Check', op, [
    particleLayer({
      name: 'record complete star',
      index: 1,
      op,
      start: 38,
      origin: [380, 382],
      target: [428, 292],
      color: 'sunflower',
      size: 14,
      starShape: true,
      rotation: 24,
      duration: 17,
      fadeFrame: 12,
    }),
    shapeLayer(
      'record success check',
      2,
      op,
      [
        pathGroup('check mark', [[-22, 0], [-5, 17], [26, -21]], 'white', 11, {
          trim: [
            { t: 41, v: [0], curve: curves.entrance },
            { t: 49, v: [100] },
          ],
        }),
        ellipse('success circle', [0, 0], [86, 86], 'mint', 'ink', 6),
      ],
      {
        position: [380, 382, 0],
        scale: [
          { t: 36, v: [70, 70, 100], curve: curves.entrance },
          { t: 44, v: [108, 108, 100], curve: curves.settle },
          { t: 52, v: [100, 100, 100] },
        ],
        opacity: [
          { t: 36, v: [0], curve: curves.entrance },
          { t: 40, v: [100] },
        ],
        ip: 36,
      },
    ),
    shapeLayer('cat paw and drawing pen', 3, op, [
      ellipse('drawing paw', [-80, -2], [54, 46], 'cat'),
      pathGroup('pen highlight', [[-54, -5], [-30, -5]], 'white', 4),
      pathGroup(
        'pen tip',
        [[-22, -12], [0, 0], [-22, 12]],
        'sunflower',
        0,
        { closed: true, fillColor: 'sunflower' },
      ),
      roundedRect('pen barrel', [-66, 0], [98, 24], 12, 'grape', 'ink', 5),
      roundedRect('pen cap', [-112, 0], [24, 26], 9, 'coral', 'ink', 4),
    ], {
      position: penPosition,
      scale: [86, 86, 100],
      rotation: [
        { t: 8, v: [-30], curve: curves.travel },
        { t: 16, v: [-30], curve: curves.travel },
        { t: 24, v: [24], curve: curves.travel },
        { t: 29, v: [-45], curve: curves.travel },
        { t: 34, v: [-37], curve: curves.settle },
        { t: 43, v: [-43] },
      ],
      opacity: [
        { t: 6, v: [0], curve: curves.entrance },
        { t: 9, v: [100] },
      ],
      ip: 6,
    }),
    shapeLayer('record coral hold', 5, op, holdShapes('coral', [54, 38]), {
      position: [150, 380, 0],
      scale: [
        { t: 10, v: [84, 84, 100], curve: curves.entrance },
        { t: 17, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 10, v: [0], curve: curves.entrance },
        { t: 14, v: [100] },
      ],
    }),
    shapeLayer('record grape hold', 6, op, holdShapes('grape', [50, 36]), {
      position: [252, 372, 0],
      scale: [
        { t: 21, v: [84, 84, 100], curve: curves.entrance },
        { t: 27, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 21, v: [0], curve: curves.entrance },
        { t: 25, v: [100] },
      ],
    }),
    shapeLayer('record sunflower hold', 7, op, holdShapes('sunflower', [50, 36]), {
      position: [330, 306, 0],
      scale: [
        { t: 27, v: [84, 84, 100], curve: curves.entrance },
        { t: 35, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 27, v: [0], curve: curves.entrance },
        { t: 31, v: [100] },
      ],
    }),
    shapeLayer(
      'pen drawn record route',
      8,
      op,
      [
        pathGroup(
          'drawn route',
          [[150, 380], [202, 350], [252, 372], [282, 342], [330, 306]],
          'coral',
          8,
          {
            trim: [
              { t: 8, v: [0], curve: curves.travel },
              { t: 16, v: [28], curve: curves.travel },
              { t: 24, v: [53], curve: curves.travel },
              { t: 29, v: [72], curve: curves.travel },
              { t: 34, v: [100] },
            ],
          },
        ),
      ],
      { position: [0, 0, 0] },
    ),
    shapeLayer(
      'record guide lines',
      9,
      op,
      [
        pathGroup('upper guide', [[122, 276], [292, 276]], 'border', 5),
        pathGroup('lower guide', [[122, 420], [292, 420]], 'border', 5),
      ],
      {
        position: [0, 0, 0],
        opacity: [
          { t: 4, v: [0], curve: curves.entrance },
          { t: 8, v: [100] },
        ],
      },
    ),
    shapeLayer(
      'record sheet',
      10,
      op,
      [
        roundedRect('record face', [0, 0], [320, 240], 34, 'cream', 'ink', 6),
        roundedRect('record depth', [0, 12], [320, 240], 34, 'border'),
      ],
      {
        position: mapPosition,
        scale: mapScale,
        rotation: [
          { t: 0, v: [3], curve: curves.entrance },
          { t: 8, v: [0] },
        ],
        opacity: [
          { t: 0, v: [0], curve: curves.entrance },
          { t: 4, v: [100] },
        ],
      },
    ),
    shapeLayer('record cat pupils', 11, op, catPupilShapes(), {
      position: [
        { t: 0, v: [326, 247, 0], curve: curves.entrance },
        { t: 10, v: [326, 203, 0], curve: curves.settle },
        { t: 18, v: [326, 209, 0] },
      ],
      scale: [70, 70, 100],
      opacity: catOpacity,
    }),
    shapeLayer('record cat face', 12, op, catFaceShapes({
      paws: false,
      pupils: false,
    }), {
      position: catPosition,
      scale: [70, 70, 100],
      opacity: catOpacity,
    }),
    shapeLayer('record cat head', 13, op, catHeadShapes(), {
      position: catPosition,
      scale: [70, 70, 100],
      opacity: catOpacity,
    }),
    shapeLayer('record cat body', 14, op, catBodyShapes(), {
      position: catPosition,
      scale: [70, 70, 100],
      opacity: catOpacity,
    }),
  ]);
}

function buildRankingEmptyInvite() {
  const op = 66;
  const catHeadPosition = [
    { t: 6, v: [236, 364, 0], curve: curves.entrance },
    { t: 10, v: [236, 340, 0], curve: curves.travel },
    { t: 20, v: [236, 256, 0], curve: curves.settle },
    { t: 28, v: [236, 262, 0] },
  ];
  const catBodyPosition = [
    { t: 10, v: [236, 372, 0], curve: curves.entrance },
    { t: 23, v: [236, 256, 0], curve: curves.settle },
    { t: 31, v: [236, 262, 0] },
  ];
  const pupilPosition = [
    { t: 6, v: [236, 364, 0], curve: curves.entrance },
    { t: 10, v: [236, 340, 0], curve: curves.travel },
    { t: 20, v: [236, 256, 0], curve: curves.settle },
    { t: 24, v: [236, 260, 0], curve: curves.entrance },
    { t: 31, v: [243, 269, 0], curve: curves.settle },
    { t: 40, v: [243, 269, 0] },
  ];

  return scene('Wanpan - Ranking Empty Invite', op, [
    particleLayer({
      name: 'ranking star left',
      index: 1,
      op,
      start: 25,
      origin: [256, 365],
      target: [118, 152],
      color: 'sunflower',
      size: 17,
      starShape: true,
      rotation: -22,
      duration: 19,
      fadeFrame: 14,
    }),
    particleLayer({
      name: 'ranking star right',
      index: 2,
      op,
      start: 27,
      origin: [256, 365],
      target: [396, 138],
      color: 'sunflower',
      size: 14,
      starShape: true,
      rotation: 26,
      duration: 19,
      fadeFrame: 14,
    }),
    particleLayer({
      name: 'ranking grape accent',
      index: 3,
      op,
      start: 29,
      origin: [256, 365],
      target: [404, 226],
      color: 'grape',
      size: 13,
      rotation: 34,
      duration: 19,
      fadeFrame: 14,
    }),
    shapeLayer(
      'route invitation arrow',
      4,
      op,
      [
        pathGroup(
          'invitation route',
          [[120, 414], [191, 389], [276, 409], [365, 374]],
          'coral',
          9,
          {
            trim: [
              { t: 26, v: [0], curve: curves.entrance },
              { t: 41, v: [100] },
            ],
          },
        ),
        pathGroup(
          'arrow tip upper',
          [[342, 354], [365, 374]],
          'coral',
          9,
          {
            trim: [
              { t: 37, v: [0], curve: curves.entrance },
              { t: 43, v: [100] },
            ],
          },
        ),
        pathGroup(
          'arrow tip lower',
          [[339, 391], [365, 374]],
          'coral',
          9,
          {
            trim: [
              { t: 37, v: [0], curve: curves.entrance },
              { t: 43, v: [100] },
            ],
          },
        ),
      ],
      { position: [0, 0, 0] },
    ),
    shapeLayer(
      'cta guide arm and paw',
      5,
      op,
      [
        pathGroup('cta guide arm', [[0, 0], [48, 34]], 'cat', 25),
        ellipse('cta guide paw', [51, 36], [50, 42], 'cat'),
      ],
      {
        position: [
          { t: 21, v: [278, 288, 0], curve: curves.entrance },
          { t: 30, v: [290, 274, 0], curve: curves.settle },
          { t: 38, v: [286, 278, 0] },
        ],
        rotation: [
          { t: 21, v: [-10], curve: curves.entrance },
          { t: 31, v: [4], curve: curves.settle },
          { t: 38, v: [0] },
        ],
        opacity: [
          { t: 21, v: [0], curve: curves.entrance },
          { t: 24, v: [100] },
        ],
      },
    ),
    shapeLayer('invitation coral hold', 6, op, holdShapes('coral', [92, 64]), {
      position: [256, 365, 0],
      scale: [
        { t: 16, v: [70, 70, 100], curve: curves.entrance },
        { t: 24, v: [106, 106, 100], curve: curves.settle },
        { t: 32, v: [100, 100, 100] },
      ],
      opacity: [
        { t: 16, v: [0], curve: curves.entrance },
        { t: 21, v: [100] },
      ],
      rotation: [
        { t: 16, v: [-6], curve: curves.entrance },
        { t: 25, v: [2], curve: curves.settle },
        { t: 33, v: [0] },
      ],
    }),
    shapeLayer('ranking left paw', 7, op, [
      ellipse('left paw', [0, 0], [58, 48], 'cat'),
    ], {
      position: [
        { t: 11, v: [174, 392, 0], curve: curves.entrance },
        { t: 24, v: [174, 302, 0], curve: curves.settle },
        { t: 31, v: [174, 306, 0] },
      ],
      opacity: [
        { t: 11, v: [0], curve: curves.entrance },
        { t: 14, v: [100] },
      ],
      scale: [90, 90, 100],
    }),
    shapeLayer('ranking pupils', 8, op, catPupilShapes(), {
      position: pupilPosition,
      scale: [90, 90, 100],
      opacity: [
        { t: 6, v: [0], curve: curves.entrance },
        { t: 9, v: [100] },
      ],
    }),
    shapeLayer('ranking cat face', 9, op, catFaceShapes({
      paws: false,
      pupils: false,
    }), {
      position: catHeadPosition,
      scale: [90, 90, 100],
      rotation: [
        { t: 6, v: [-4], curve: curves.entrance },
        { t: 20, v: [1], curve: curves.settle },
        { t: 28, v: [0] },
        { t: 31, v: [3], curve: curves.settle },
        { t: 40, v: [0] },
      ],
      opacity: [
        { t: 6, v: [0], curve: curves.entrance },
        { t: 9, v: [100] },
      ],
    }),
    shapeLayer('ranking cat head', 10, op, catHeadShapes(), {
      position: catHeadPosition,
      scale: [90, 90, 100],
      rotation: [
        { t: 6, v: [-4], curve: curves.entrance },
        { t: 20, v: [1], curve: curves.settle },
        { t: 28, v: [0] },
        { t: 31, v: [3], curve: curves.settle },
        { t: 40, v: [0] },
      ],
      opacity: [
        { t: 6, v: [0], curve: curves.entrance },
        { t: 9, v: [100] },
      ],
    }),
    shapeLayer(
      'ranking podium',
      12,
      op,
      [
        roundedRect('podium face', [0, 0], [330, 88], 30, 'cream', 'ink', 6),
        roundedRect('podium depth', [0, 10], [330, 88], 30, 'border'),
      ],
      {
        position: [256, 420, 0],
        scale: [
          { t: 0, v: [86, 100, 100], curve: curves.entrance },
          { t: 8, v: [100, 100, 100] },
        ],
        opacity: [
          { t: 0, v: [0], curve: curves.entrance },
          { t: 4, v: [100] },
        ],
      },
    ),
    shapeLayer('ranking cat body', 11, op, catBodyShapes({ tail: false }), {
      position: catBodyPosition,
      scale: [90, 90, 100],
      opacity: [
        { t: 10, v: [0], curve: curves.entrance },
        { t: 14, v: [100] },
      ],
    }),
  ]);
}

const animationOutputs = [
  { sceneDir: 'scene-1', file: 'send-success.json', animation: buildSendSuccess() },
  {
    sceneDir: 'scene-2',
    file: 'grade-milestone.json',
    animation: buildGradeMilestone(),
  },
  {
    sceneDir: 'scene-3',
    file: 'route-published.json',
    animation: buildRoutePublished(),
  },
  {
    sceneDir: 'scene-4',
    file: 'ranking-encouragement.json',
    animation: buildRankingEmptyInvite(),
  },
];

fs.mkdirSync(PLAYER_PROJECT, { recursive: true });
fs.mkdirSync(APP_ASSETS, { recursive: true });

for (const output of animationOutputs) {
  const sceneDirectory = path.join(PLAYER_PROJECT, output.sceneDir);
  fs.mkdirSync(sceneDirectory, { recursive: true });
  const serialized = `${JSON.stringify(output.animation, null, 2)}\n`;
  fs.writeFileSync(path.join(sceneDirectory, 'lottie.json'), serialized);
  fs.writeFileSync(
    path.join(sceneDirectory, 'controls.json'),
    `${JSON.stringify(controls, null, 2)}\n`,
  );
  fs.writeFileSync(path.join(APP_ASSETS, output.file), serialized);
  console.log(`${output.sceneDir}: ${output.file} (${serialized.length} bytes)`);
}
