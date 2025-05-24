import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { cn } from "@/lib/utils";
import "./globals.css";
import Provider from "@/components/queryProvider";
import { Toaster } from "@/components/ui/sonner";
import { NuqsAdapter } from 'nuqs/adapters/next/app';

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
	title: "Jira",
	description: "Project management app",
};

export default function RootLayout({
	children,
}: Readonly<{
	children: React.ReactNode;
}>) {
	return (
		<html lang="en">
			<body className={"antialiased min-h-screen"}>
				<NuqsAdapter>
					<Provider>
						<Toaster />
						{children}
					</Provider>
				</NuqsAdapter>
			</body>
		</html>
	);
}
