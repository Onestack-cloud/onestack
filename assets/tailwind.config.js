// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = {
  darkMode: 'media',
  content: [
    "./js/**/*.js",
    "../lib/onestack_web.ex",
    "../lib/onestack_web/**/*.*ex",
    "node_modules/preline/dist/*.js",
    './node_modules/flowbite/**/*.js'
  ],
  theme: {
    extend: {
      // colors: {
      //   brand: "#FD4F00",
      // },
      fontFamily: {
        pixel_title: ["VT323", "sans-serif"],
      },
      animation: {
        'fadeIn': 'fadeIn 1s ease-in-out',
        'bounce-slow': 'bounce 3s ease-in-out infinite',
        'bounce-delayed': 'bounce 3s ease-in-out 1s infinite',
        'float': 'float 6s ease-in-out infinite',
        'float-delayed': 'float 6s ease-in-out 3s infinite',
        'pulse': 'pulse 4s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-10px)' },
        },
      },
      transitionDuration: {
        '2000': '2000ms',
      },
      perspective: {
        '1000': '1000px',
      },
    },
    container: {
      center: true,
      padding: {
        DEFAULT: "1rem",
        sm: "2rem",
        lg: "4rem",
        xl: "6rem",
        "2xl": "8rem",
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("@tailwindcss/forms"),
    require("@tailwindcss/typography"),
    require("preline/plugin"),
    require('flowbite/plugin'),

    // require("daisyui"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant("phx-no-feedback", [
        ".phx-no-feedback&",
        ".phx-no-feedback &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        ".phx-click-loading&",
        ".phx-click-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        ".phx-submit-loading&",
        ".phx-submit-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        ".phx-change-loading&",
        ".phx-change-loading &",
      ]),
    ),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized");
      let values = {};
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach((file) => {
          let name = path.basename(file, ".svg") + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, "");
            let size = theme("spacing.6");
            if (name.endsWith("-mini")) {
              size = theme("spacing.5");
            } else if (name.endsWith("-micro")) {
              size = theme("spacing.4");
            }
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              "-webkit-mask": `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              "mask-repeat": "no-repeat",
              "background-color": "currentColor",
              "vertical-align": "middle",
              display: "inline-block",
              width: size,
              height: size,
            };
          },
        },
        { values },
      );
    }),
  ],
  // daisyui: {
  //   themes: ["business"],
  //   base: true, // applies background color and foreground color for root element by default
  //   styled: true, // include daisyUI colors and design decisions for all components
  //   utils: true, // adds responsive and modifier utility classes
  //   logs: true, // Shows info about daisyUI version and used config in the console when building your CSS
  //   // themeRoot: ":root", //
  // }
  // daisyui: {
  //   themes: [
  //     {
  //       business: {
  //         ...require("daisyui/src/theming/themes")["lofi"],
  //         // primary: "#d1d5db",
  //         // secondary: "#ffffff",
  //       },
  //     },
  //   ],
  //   base: true, // applies background color and foreground color for root element by default
  //   styled: true, // include daisyUI colors and design decisions for all components
  //   utils: true, // adds responsive and modifier utility classes
  //   logs: true, // Shows info about daisyUI version and used config in the console when building your CSS
  // },
  daisyui: {
    themes: [
      {
        light: {
          ...require("daisyui/src/theming/themes").light,
          primary: "#1b77ff",
          "primary-content": "#ffffff",
          secondary: "#494949",
          neutral: "#03131a",
          info: "#00e1ff",
          success: "#90ca27",
          warning: "#ff8800",
          error: "#ff7f7f",
          "--rounded-box": "0.25rem",
          "--rounded-btn": "0.25rem",
        },
        dark: {
          ...require("daisyui/src/theming/themes").dark,
          primary: "#1b77ff",
          "primary-content": "#ffffff",
          secondary: "#494949",
          neutral: "#03131a",
          info: "#00e1ff",
          success: "#90ca27",
          warning: "#ff8800",
          error: "#ff7f7f",
          "base-100": "#14181c",
          "base-200": "#1e2328",
          "base-300": "#28323c",
          "base-content": "#dcebfa",
          "--rounded-box": "0.25rem",
          "--rounded-btn": "0.25rem",
        },
      },
    ],
  },
};
