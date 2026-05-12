import { useState } from "react";
import { motion } from "framer-motion";
import { Star } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";
import { Textarea } from "@/components/ui/textarea";

interface RatingPromptProps {
  driverName: string;
  onSubmit: (rating: number, review: string) => void;
}

export function RatingPrompt({ driverName, onSubmit }: RatingPromptProps) {
  const [rating, setRating] = useState(5);
  const [review, setReview] = useState("");

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="space-y-4"
    >
      <div className="text-center">
        <p className="font-semibold text-foreground">Notez votre expérience</p>
        <p className="text-xs text-muted-foreground">Évaluez {driverName} pour finaliser la transaction</p>
      </div>

      <div className="flex justify-center">
        <StarRow value={rating} />
      </div>

      <div className="px-2">
        <Slider
          value={[rating]}
          min={1}
          max={5}
          step={0.25}
          onValueChange={(v) => setRating(v[0])}
        />
        <div className="flex justify-between text-[10px] text-muted-foreground mt-1">
          <span>1</span><span>2</span><span>3</span><span>4</span><span>5</span>
        </div>
        <p className="text-center text-sm font-semibold text-foreground mt-2">
          {rating.toFixed(2)} / 5
        </p>
      </div>

      <Textarea
        placeholder="Commentaire (optionnel)"
        value={review}
        onChange={(e) => setReview(e.target.value)}
        className="min-h-[80px]"
      />

      <Button onClick={() => onSubmit(rating, review)} className="w-full h-12 gradient-primary">
        Finaliser la transaction
      </Button>
    </motion.div>
  );
}

function StarRow({ value }: { value: number }) {
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map((i) => {
        const fill = Math.max(0, Math.min(1, value - (i - 1)));
        return (
          <div key={i} className="relative w-8 h-8">
            <Star className="w-8 h-8 text-muted-foreground/40" />
            <div
              className="absolute inset-0 overflow-hidden"
              style={{ width: `${fill * 100}%` }}
            >
              <Star className="w-8 h-8 fill-secondary text-secondary" />
            </div>
          </div>
        );
      })}
    </div>
  );
}
