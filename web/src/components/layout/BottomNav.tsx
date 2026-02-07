import { NavLink } from 'react-router-dom';
import {
  HiOutlineRectangleStack,
  HiOutlineCog6Tooth,
  HiRectangleStack,
  HiCog6Tooth,
} from 'react-icons/hi2';
import { PiWaveformLight } from 'react-icons/pi';
import { cn } from '../../lib/cn';
import { ROUTES } from '../../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface NavItem {
  path: string;
  label: string;
  icon: React.ReactNode;
  activeIcon: React.ReactNode;
}

// ═══════════════════════════════════════════════════════════════════════════
// NAV ITEMS
// ═══════════════════════════════════════════════════════════════════════════

const navItems: NavItem[] = [
  {
    path: ROUTES.CUES,
    label: 'Subjects',
    icon: <HiOutlineRectangleStack className="w-6 h-6" />,
    activeIcon: <HiRectangleStack className="w-6 h-6" />,
  },
  {
    path: ROUTES.HISTORY,
    label: 'History',
    icon: <PiWaveformLight className="w-6 h-6" />,
    activeIcon: <PiWaveformLight className="w-6 h-6" />,
  },
  {
    path: ROUTES.SETTINGS,
    label: 'Settings',
    icon: <HiOutlineCog6Tooth className="w-6 h-6" />,
    activeIcon: <HiCog6Tooth className="w-6 h-6" />,
  },
];

// ═══════════════════════════════════════════════════════════════════════════
// BOTTOM NAV
// ═══════════════════════════════════════════════════════════════════════════

export function BottomNav() {
  return (
    <nav className="fixed bottom-0 left-0 right-0 z-sticky bg-app-sand-light border-t border-border safe-bottom">
      <div className="flex items-center justify-around h-16 max-w-lg mx-auto">
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            className="flex flex-1 h-full items-center justify-center"
          >
            {({ isActive }) => (
              <span
                className={cn(
                  'flex items-center gap-2 px-4 py-2 rounded-full',
                  'transition-all duration-300 ease-out',
                  isActive
                    ? 'bg-app-green-strong text-app-sand-light'
                    : 'text-text-tertiary hover:text-text-secondary'
                )}
              >
                {isActive ? item.activeIcon : item.icon}
                <span className="text-caption font-medium">
                  {item.label}
                </span>
              </span>
            )}
          </NavLink>
        ))}
      </div>
    </nav>
  );
}
