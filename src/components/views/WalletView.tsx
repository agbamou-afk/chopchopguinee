import { motion } from "framer-motion";
import { ArrowUpRight, ArrowDownLeft, History, CreditCard, QrCode, Plus } from "lucide-react";
import { WalletCard } from "@/components/home/WalletCard";

const transactions = [
  {
    id: 1,
    type: "out" as const,
    title: "Course Moto",
    description: "Madina → Kipé",
    amount: -15000,
    date: "Aujourd'hui, 14:30",
  },
  {
    id: 2,
    type: "in" as const,
    title: "Reçu de Amadou",
    description: "Remboursement",
    amount: 50000,
    date: "Aujourd'hui, 10:15",
  },
  {
    id: 3,
    type: "out" as const,
    title: "Commande repas",
    description: "Chez Mama Fatoumata",
    amount: -35000,
    date: "Hier, 19:45",
  },
  {
    id: 4,
    type: "in" as const,
    title: "Recharge portefeuille",
    description: "Orange Money",
    amount: 200000,
    date: "Hier, 08:00",
  },
  {
    id: 5,
    type: "out" as const,
    title: "Achat Marché",
    description: "Smartphone case",
    amount: -25000,
    date: "20 Jan, 16:20",
  },
];

const quickActions = [
  { id: "send", icon: ArrowUpRight, label: "Envoyer", color: "gradient-primary" },
  { id: "receive", icon: ArrowDownLeft, label: "Recevoir", color: "gradient-secondary" },
  { id: "scan", icon: QrCode, label: "Scanner", color: "bg-foreground" },
  { id: "add", icon: Plus, label: "Recharger", color: "bg-primary" },
];

export function WalletView() {
  const formatMoney = (amount: number) =>
    new Intl.NumberFormat("fr-GN").format(Math.abs(amount));

  return (
    <div className="max-w-md mx-auto">
      {/* Header */}
      <motion.header
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="px-4 pt-6 pb-4"
      >
        <h1 className="text-2xl font-bold text-foreground mb-4">Portefeuille</h1>
        <WalletCard balance={2500000} />
      </motion.header>

      {/* Quick actions */}
      <div className="px-4 mb-6">
        <div className="grid grid-cols-4 gap-3">
          {quickActions.map((action, index) => (
            <motion.button
              key={action.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.05 }}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              className="flex flex-col items-center"
            >
              <div className={`p-3 rounded-2xl ${action.color} shadow-soft mb-2`}>
                <action.icon className="w-5 h-5 text-primary-foreground" />
              </div>
              <span className="text-xs font-medium text-foreground">{action.label}</span>
            </motion.button>
          ))}
        </div>
      </div>

      {/* Payment methods */}
      <div className="px-4 mb-6">
        <h2 className="text-lg font-semibold text-foreground mb-3">Moyens de paiement</h2>
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl p-4 shadow-card"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-primary/10">
              <CreditCard className="w-5 h-5 text-primary" />
            </div>
            <div className="flex-1">
              <p className="font-medium text-foreground">Orange Money</p>
              <p className="text-sm text-muted-foreground">+224 6** *** **89</p>
            </div>
            <span className="text-xs font-medium text-primary bg-primary/10 px-2 py-1 rounded-full">
              Principal
            </span>
          </div>
        </motion.div>
      </div>

      {/* Transaction history */}
      <div className="px-4 pb-6">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-semibold text-foreground">Historique</h2>
          <button className="text-sm font-medium text-primary flex items-center gap-1">
            <History className="w-4 h-4" />
            Voir tout
          </button>
        </div>

        <div className="space-y-3">
          {transactions.map((tx, index) => (
            <motion.div
              key={tx.id}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: index * 0.05 }}
              className="bg-card rounded-2xl p-4 shadow-card flex items-center gap-3"
            >
              <div
                className={`p-2 rounded-xl ${
                  tx.type === "in" ? "bg-success/10" : "bg-destructive/10"
                }`}
              >
                {tx.type === "in" ? (
                  <ArrowDownLeft
                    className={`w-5 h-5 ${
                      tx.type === "in" ? "text-success" : "text-destructive"
                    }`}
                  />
                ) : (
                  <ArrowUpRight className="w-5 h-5 text-destructive" />
                )}
              </div>
              <div className="flex-1">
                <p className="font-medium text-foreground text-sm">{tx.title}</p>
                <p className="text-xs text-muted-foreground">{tx.description}</p>
              </div>
              <div className="text-right">
                <p
                  className={`font-semibold text-sm ${
                    tx.type === "in" ? "text-success" : "text-foreground"
                  }`}
                >
                  {tx.type === "in" ? "+" : "-"}{formatMoney(tx.amount)} GNF
                </p>
                <p className="text-xs text-muted-foreground">{tx.date}</p>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
}
