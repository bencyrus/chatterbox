import { NavLink } from 'react-router-dom';
import {
  HiOutlineMicrophone,
  HiOutlineClock,
  HiOutlineCog6Tooth,
  HiMicrophone,
  HiClock,
  HiCog6Tooth,
} from 'react-icons/hi2';
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
    label: 'Practice',
    icon: <HiOutlineMicrophone className="w-6 h-6" />,
    activeIcon: <HiMicrophone className="w-6 h-6" />,
  },
  {
    path: ROUTES.HISTORY,
    label: 'History',
    icon: <HiOutlineClock className="w-6 h-6" />,
    activeIcon: <HiClock className="w-6 h-6" />,
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
    <nav className="fixed bottom-0 left-0 right-0 z-sticky bg-surface-primary border-t border-border-primary safe-bottom">
      <div className="flex items-center justify-around h-16 max-w-lg mx-auto">
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            className={({ isActive }) =>
              cn(
                'flex flex-col items-center justify-center flex-1 h-full',
                'transition-colors duration-150',
                isActive
                  ? 'text-brand-primary'
                  : 'text-text-tertiary hover:text-text-secondary'
              )
            }
          >
            {({ isActive }) => (
              <>
                {isActive ? item.activeIcon : item.icon}
                <span className="text-caption mt-0.5 font-medium">
                  {item.label}
                </span>
              </>
            )}
          </NavLink>
        ))}
      </div>
    </nav>
  );
}
