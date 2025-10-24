import { StreamChat, type UserResponse } from "stream-chat";

type SeedUser = Pick<UserResponse, "id" | "name" | "image">;

const apiKey = process.env.STREAM_API_KEY ?? "";
const apiSecret = process.env.STREAM_API_SECRET ?? "";

if (!apiKey || !apiSecret) {
  console.error("Missing STREAM_API_KEY or STREAM_API_SECRET environment variables.");
  console.error("Run with: STREAM_API_KEY=xxx STREAM_API_SECRET=yyy npx ts-node scripts/bootstrapChannels.ts");
  process.exit(1);
}

const defaultUsers: SeedUser[] = [
  { id: "babel-demo-1", name: "Ava" },
  { id: "babel-demo-2", name: "Ben" },
  { id: "babel-demo-3", name: "Chloe" }
];

const membersFlag = readFlag("--members");
const memberSource = process.env.BABEL_USER_IDS ?? membersFlag ?? "";
const memberIds = memberSource
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

const users: SeedUser[] = memberIds.length
  ? memberIds.map((id, index) => ({
      id,
      name: `Demo User ${index + 1}`
    }))
  : defaultUsers;

async function main() {
  const client = StreamChat.getInstance(apiKey, apiSecret);

  console.log(`Upserting ${users.length} users…`);
  await client.upsertUsers(users);

  const userIds = users.map((user) => user.id);

  await seedGeneralChannel(client, userIds);
  await seedDmChannel(client, userIds);

  console.log("Seed complete. Users:", userIds.join(", "));
}

async function seedGeneralChannel(client: StreamChat, members: string[]) {
  const channel = client.channel("messaging", "babel-general", {
    name: "Babel General",
    created_by_id: members[0] ?? "seed-bot",
    members,
  });

  console.log(`Creating/refreshing channel #${channel.id}…`);

  let created = false;
  try {
    await channel.create();
    created = true;
  } catch (error) {
    if (isAlreadyExistsError(error)) {
      console.log("Channel already exists; skipping create.");
      await channel.watch({ state: true, presence: false, message_limit: 1 });
    } else {
      throw error;
    }
  }

  if (created && members.length > 0) {
    await channel.sendMessage({
      text: "Welcome to Babel General!",
      user_id: members[0],
    });
  }
}

async function seedDmChannel(client: StreamChat, members: string[]) {
  if (members.length < 2) {
    console.log("Skipping DM channel seeding (need at least 2 members).");
    return;
  }

  const dmMembers = members.slice(0, 2);
  const dmChannel = client.channel("messaging", {
    members: dmMembers,
    created_by_id: dmMembers[0],
  });

  console.log(`Creating DM channel for ${dmMembers.join(" & ")}…`);

  let created = false;
  try {
    await dmChannel.create();
    created = true;
  } catch (error) {
    if (isAlreadyExistsError(error)) {
      console.log("DM channel already exists; skipping create.");
      await dmChannel.watch({ state: true, presence: false, message_limit: 1 });
    } else {
      throw error;
    }
  }

  if (created) {
    await dmChannel.sendMessage({
      text: "Hey there! This is your private chat room.",
      user_id: dmMembers[0],
    });
  }
}

function readFlag(name: string): string | undefined {
  const index = process.argv.findIndex((arg) => arg === name);
  if (index >= 0) {
    return process.argv[index + 1];
  }
  const prefixed = process.argv.find((arg) => arg.startsWith(`${name}=`));
  if (prefixed) {
    return prefixed.split("=")[1];
  }
  return undefined;
}

function isAlreadyExistsError(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && (error as { code?: number }).code === 17;
}

main().catch((error) => {
  console.error("Bootstrap failed:", error);
  process.exit(1);
});
