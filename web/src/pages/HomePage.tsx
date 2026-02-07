import { Link } from 'react-router-dom';
import {
  HiOutlineArrowRight,
  HiOutlineRectangleStack,
  HiOutlineMicrophone,
  HiOutlineClock,
  HiOutlineDocumentChartBar,
} from 'react-icons/hi2';
import { ROUTES } from '../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// HOME PAGE
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Home page - public landing page
 * Accessible to both authenticated and unauthenticated users
 */
function HomePage() {
  return (
    <div className="min-h-screen bg-surface-primary">
      <header className="sticky top-0 z-sticky bg-white border-b border-border-secondary">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <img
              src="https://storage.googleapis.com/chatterbox-public-assets/public-chatterbox-logo-color-bg.png"
              alt="Chatterbox"
              className="w-10 h-10 rounded-2xl shadow-card"
            />
            <span className="text-heading-sm font-semibold text-text-primary">
              Chatterbox
            </span>
          </div>
          <div className="flex items-center gap-3">
            <Link
              to={ROUTES.APP}
              className="btn-base bg-app-green-strong text-white hover:bg-app-green-dark active:bg-app-green-dark shadow-button text-label-md px-5 py-2"
            >
              <span>Open App</span>
              <HiOutlineArrowRight className="w-4 h-4 relative top-[1px] shrink-0" />
            </Link>
          </div>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-6 pb-16">
        <section className="py-12 max-w-2xl">
          <h1 className="text-heading-lg font-semibold text-text-primary">
            Short, focused speaking practice
          </h1>
          <p className="text-body-lg text-text-secondary mt-4">
            Chatterbox is a simple way to practice speaking with prompts, record
            when you are ready, and track how you improve over time.
          </p>
          <div className="flex flex-wrap gap-3 mt-6">
            <Link
              to={ROUTES.APP}
              className="btn-base bg-app-green-strong text-white hover:bg-app-green-dark active:bg-app-green-dark shadow-button text-label-lg px-8 py-4"
            >
              <span>Open App</span>
              <HiOutlineArrowRight className="w-5 h-5 relative top-[1px] shrink-0" />
            </Link>
          </div>
        </section>

        <section className="grid gap-4 max-w-3xl">
          <div className="rounded-2xl bg-app-beige p-5">
            <p className="text-body-md text-text-primary font-medium flex items-center gap-2">
              <HiOutlineRectangleStack className="w-5 h-5 text-app-green-strong shrink-0" />
              Choose a cue card
            </p>
            <p className="text-body-sm text-text-secondary">
              Pick a subject to talk about and open it when you are ready.
            </p>
          </div>
          <div className="rounded-2xl bg-app-beige p-5">
            <p className="text-body-md text-text-primary font-medium flex items-center gap-2">
              <HiOutlineMicrophone className="w-5 h-5 text-app-green-strong shrink-0" />
              Record your response
            </p>
            <p className="text-body-sm text-text-secondary">
              Speak naturally, then replay to hear yourself.
            </p>
          </div>
          <div className="rounded-2xl bg-app-beige p-5">
            <p className="text-body-md text-text-primary font-medium flex items-center gap-2">
              <HiOutlineClock className="w-5 h-5 text-app-green-strong shrink-0" />
              Review your history
            </p>
            <p className="text-body-sm text-text-secondary">
              Access past recordings whenever you want.
            </p>
          </div>
          <div className="rounded-2xl bg-app-beige p-5">
            <p className="text-body-md text-text-primary font-medium flex items-center gap-2">
              <HiOutlineDocumentChartBar className="w-5 h-5 text-app-green-strong shrink-0" />
              Get a progress report
            </p>
            <p className="text-body-sm text-text-secondary">
              See what improved, repeated mistakes, and try the same subject
              later to measure progress.
            </p>
          </div>
        </section>
      </main>

      <footer className="border-t border-border-secondary bg-white">
        <div className="max-w-6xl mx-auto px-6 py-8 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
          <p className="text-body-sm text-text-tertiary">
            Chatterbox - speak with confidence, every day.
          </p>
          <div className="flex items-center gap-4">
            <Link
              to={ROUTES.PRIVACY}
              className="text-body-sm text-text-secondary hover:text-text-primary"
            >
              Privacy Policy
            </Link>
            <Link
              to={ROUTES.APP}
              className="text-body-sm text-text-secondary hover:text-text-primary"
            >
              Open App
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default HomePage;
