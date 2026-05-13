const BANNERS = [
  { title: "Livraison disponible avec CHOP CHOP", sub: "Faites livrer vos achats partout à Conakry", grad: "from-emerald-500 to-emerald-700" },
  { title: "Trouvez des offres près de vous", sub: "Annonces de votre quartier", grad: "from-amber-500 to-orange-600" },
  { title: "Achetez et faites livrer rapidement", sub: "Pickup + Delivery en un clic", grad: "from-sky-500 to-indigo-600" },
  { title: "Nouveaux vendeurs vérifiés", sub: "Marchands de confiance", grad: "from-rose-500 to-pink-600" },
] as const;

export function FeaturedBanners() {
  return (
    <div className="flex gap-3 overflow-x-auto scrollbar-none -mx-4 px-4 pb-1">
      {BANNERS.map((b, i) => (
        <div
          key={i}
          className={`shrink-0 w-72 h-28 rounded-2xl p-4 text-white bg-gradient-to-br ${b.grad} shadow-card flex flex-col justify-between`}
        >
          <div className="text-xs uppercase tracking-wider opacity-80">CHOP CHOP Marché</div>
          <div>
            <p className="font-semibold leading-tight">{b.title}</p>
            <p className="text-xs opacity-90 mt-1">{b.sub ?? ""}</p>
          </div>
        </div>
      ))}
    </div>
  );
}