import { HiOutlineCheck, HiOutlineGlobeAlt } from 'react-icons/hi2';
import { Card, CardContent } from '../ui/Card';
import { Spinner } from '../ui/Spinner';
import { cn } from '../../lib/cn';
import { LANGUAGE_NAMES } from '../../lib/constants';
import { useAvailableLanguages } from '../../contexts/ConfigContext';
import { useProfile } from '../../contexts/ProfileContext';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface LanguageSelectorProps {
  /** Current selected language */
  selectedLanguage: string | null;
  /** On language select */
  onSelect: (language: string) => void;
  /** Whether selection is loading */
  isLoading?: boolean;
  /** Language currently being loaded */
  loadingLanguage?: string | null;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// LANGUAGE SELECTOR
// ═══════════════════════════════════════════════════════════════════════════

export function LanguageSelector({
  selectedLanguage,
  onSelect,
  isLoading = false,
  loadingLanguage = null,
  className,
}: LanguageSelectorProps) {
  const availableLanguages = useAvailableLanguages();

  if (availableLanguages.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="py-6 text-center">
          <p className="text-body-md text-text-secondary">
            No languages available
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className={cn('space-y-2', className)}>
      {availableLanguages.map((language) => {
        const isSelected = language === selectedLanguage;
        const isThisLoading = loadingLanguage === language;
        const languageName = LANGUAGE_NAMES[language] || language;

        return (
          <Card
            key={language}
            interactive={!isLoading}
            onClick={() => !isLoading && onSelect(language)}
            className={cn(
              'transition-colors duration-150',
              isSelected && 'border-brand-primary bg-brand-primary/5'
            )}
          >
            <CardContent className="flex items-center gap-4 py-3">
              {/* Language icon */}
              <div
                className={cn(
                  'w-10 h-10 rounded-full flex items-center justify-center',
                  isSelected
                    ? 'bg-brand-primary text-white'
                    : 'bg-surface-tertiary text-text-secondary'
                )}
              >
                <HiOutlineGlobeAlt className="w-5 h-5" />
              </div>

              {/* Language name */}
              <div className="flex-1 min-w-0">
                <p
                  className={cn(
                    'text-body-md font-medium',
                    isSelected ? 'text-brand-primary' : 'text-text-primary'
                  )}
                >
                  {languageName}
                </p>
              </div>

              {/* Status indicator */}
              <div className="w-6 h-6 flex items-center justify-center">
                {isThisLoading ? (
                  <Spinner size="sm" />
                ) : isSelected ? (
                  <HiOutlineCheck className="w-5 h-5 text-brand-primary" />
                ) : null}
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
