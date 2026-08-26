export function highestUnlockedSetupStep(completedSteps: ReadonlySet<number>, totalSteps: number): number {
  let highestUnlocked = 0;
  while (highestUnlocked < totalSteps - 1 && completedSteps.has(highestUnlocked)) {
    highestUnlocked += 1;
  }
  return highestUnlocked;
}

export function canSelectSetupStep(index: number, completedSteps: ReadonlySet<number>, totalSteps: number): boolean {
  return index >= 0 && index <= highestUnlockedSetupStep(completedSteps, totalSteps);
}
