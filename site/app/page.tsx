import { SiteHeader } from '@/components/landing/site-header';
import { HeroSection } from '@/components/landing/hero-section';
import { PromoFilm } from '@/components/landing/promo-film';
import { SiteFooter } from '@/components/landing/site-footer';

export default function Home() {
  return (
    <div className="landing">
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <SiteHeader />
      <main id="main">
        <HeroSection />
        <PromoFilm />
      </main>
      <SiteFooter />
    </div>
  );
}
