import type { Config } from 'tailwindcss';
import typography from '@tailwindcss/typography';

export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      // ═══════════════════════════════════════════════════════════════
      // COLOR SYSTEM
      // ═══════════════════════════════════════════════════════════════
      colors: {
        // Brand Colors
        brand: {
          50:  '#f0f9ff',
          100: '#e0f2fe',
          200: '#bae6fd',
          300: '#7dd3fc',
          400: '#38bdf8',
          500: '#0ea5e9',  // Primary brand color
          600: '#0284c7',
          700: '#0369a1',
          800: '#075985',
          900: '#0c4a6e',
          950: '#082f49',
        },

        // App (iOS) Colors
        app: {
          green: '#b3cbc0',
          'green-dark': '#7fa395',
          'green-strong': '#5f7f73',
          'green-deep': '#4a655c',
          'green-mid': '#55756a',
          blue: '#bec8e3',
          'blue-dark': '#8f9bb8',
          beige: '#f7e4d6',
          'beige-dark': '#e5d2c4',
          sand: '#eeeee6',
        },
        
        // Semantic Colors
        surface: {
          DEFAULT: '#ffffff',
          secondary: '#f8fafc',
          tertiary: '#f1f5f9',
          inverse: '#0f172a',
        },
        
        border: {
          DEFAULT: '#e2e8f0',
          strong: '#cbd5e1',
          inverse: '#334155',
        },
        
        text: {
          primary: '#0f172a',
          secondary: '#475569',
          tertiary: '#94a3b8',
          inverse: '#ffffff',
          brand: '#0284c7',
        },
        
        // Status Colors
        success: {
          50:  '#f0fdf4',
          100: '#dcfce7',
          500: '#7fa395',
          600: '#5f7f73',
          700: '#4a655c',
        },
        
        warning: {
          50:  '#fffbeb',
          100: '#fef3c7',
          500: '#f59e0b',
          600: '#d97706',
          700: '#b45309',
        },
        
        error: {
          50:  '#fef2f2',
          100: '#fee2e2',
          500: '#ef4444',
          600: '#dc2626',
          700: '#b91c1c',
        },
        
        // Recording specific
        recording: {
          idle: '#64748b',
          active: '#ef4444',
          paused: '#f59e0b',
        },
      },
      
      // ═══════════════════════════════════════════════════════════════
      // TYPOGRAPHY
      // ═══════════════════════════════════════════════════════════════
      fontFamily: {
        sans: [
          'Inter',
          'system-ui',
          '-apple-system',
          'BlinkMacSystemFont',
          'Segoe UI',
          'Roboto',
          'sans-serif',
        ],
        mono: [
          'JetBrains Mono',
          'Menlo',
          'Monaco',
          'Consolas',
          'monospace',
        ],
      },
      
      fontSize: {
        // Display
        'display-lg': ['3rem', { lineHeight: '1.1', fontWeight: '700' }],
        'display-md': ['2.25rem', { lineHeight: '1.2', fontWeight: '700' }],
        'display-sm': ['1.875rem', { lineHeight: '1.25', fontWeight: '600' }],
        
        // Headings
        'heading-lg': ['1.5rem', { lineHeight: '1.3', fontWeight: '600' }],
        'heading-md': ['1.25rem', { lineHeight: '1.4', fontWeight: '600' }],
        'heading-sm': ['1.125rem', { lineHeight: '1.4', fontWeight: '600' }],
        
        // Body
        'body-lg': ['1.125rem', { lineHeight: '1.6' }],
        'body-md': ['1rem', { lineHeight: '1.6' }],
        'body-sm': ['0.875rem', { lineHeight: '1.5' }],
        
        // Labels & Captions
        'label-lg': ['0.875rem', { lineHeight: '1.4', fontWeight: '500' }],
        'label-md': ['0.8125rem', { lineHeight: '1.4', fontWeight: '500' }],
        'label-sm': ['0.75rem', { lineHeight: '1.4', fontWeight: '500' }],
        
        'caption': ['0.75rem', { lineHeight: '1.4' }],
      },
      
      // ═══════════════════════════════════════════════════════════════
      // SPACING
      // ═══════════════════════════════════════════════════════════════
      spacing: {
        // Semantic spacing
        'page-x': '1rem',
        'page-y': '1.5rem',
        'section': '2rem',
        'card': '1rem',
        'stack-xs': '0.25rem',
        'stack-sm': '0.5rem',
        'stack-md': '1rem',
        'stack-lg': '1.5rem',
        'stack-xl': '2rem',
        'inline-xs': '0.25rem',
        'inline-sm': '0.5rem',
        'inline-md': '0.75rem',
        'inline-lg': '1rem',
      },
      
      // ═══════════════════════════════════════════════════════════════
      // BORDERS & RADII
      // ═══════════════════════════════════════════════════════════════
      borderRadius: {
        'card': '0.75rem',
        'button': '0.5rem',
        'input': '0.5rem',
        'badge': '9999px',
        'avatar': '9999px',
      },
      
      // ═══════════════════════════════════════════════════════════════
      // SHADOWS
      // ═══════════════════════════════════════════════════════════════
      boxShadow: {
        'card': '0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)',
        'card-hover': '0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)',
        'dropdown': '0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)',
        'modal': '0 25px 50px -12px rgb(0 0 0 / 0.25)',
        'button': '0 1px 2px 0 rgb(0 0 0 / 0.05)',
        'input-focus': '0 0 0 3px rgb(14 165 233 / 0.2)',
      },
      
      // ═══════════════════════════════════════════════════════════════
      // ANIMATIONS
      // ═══════════════════════════════════════════════════════════════
      animation: {
        'fade-in': 'fadeIn 0.2s ease-out',
        'slide-up': 'slideUp 0.2s ease-out',
        'slide-down': 'slideDown 0.2s ease-out',
        'pulse-recording': 'pulseRecording 1.5s ease-in-out infinite',
        'spin-slow': 'spin 1.5s linear infinite',
      },
      
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { opacity: '0', transform: 'translateY(10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        slideDown: {
          '0%': { opacity: '0', transform: 'translateY(-10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        pulseRecording: {
          '0%, 100%': { opacity: '1', transform: 'scale(1)' },
          '50%': { opacity: '0.7', transform: 'scale(1.05)' },
        },
      },
      
      // ═══════════════════════════════════════════════════════════════
      // BREAKPOINTS (mobile-first)
      // ═══════════════════════════════════════════════════════════════
      screens: {
        'xs': '375px',
        'sm': '640px',
        'md': '768px',
        'lg': '1024px',
        'xl': '1280px',
      },
      
      // ═══════════════════════════════════════════════════════════════
      // Z-INDEX
      // ═══════════════════════════════════════════════════════════════
      zIndex: {
        'dropdown': '50',
        'sticky': '100',
        'modal-backdrop': '200',
        'modal': '210',
        'toast': '300',
        'tooltip': '400',
      },
    },
  },
  plugins: [
    typography,
  ],
} satisfies Config;
